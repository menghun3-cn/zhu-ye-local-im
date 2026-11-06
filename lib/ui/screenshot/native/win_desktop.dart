import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

import 'package:ffi/ffi.dart';
import 'package:image/image.dart' as img;
import 'package:win32/win32.dart';

/// The Win32 facts the screenshot feature needs and no plugin offers.
///
/// Everything here is Windows-only by construction: the whole feature is, so
/// the callers live behind the same platform check the rest of the desktop
/// code uses. Coordinates are **physical pixels** throughout — Win32 speaks
/// physical pixels, and the Dart side converts to and from Flutter's logical
/// ones exactly once, at the window boundary.
///
/// The pieces, and why each is here rather than in a package:
///
/// * [virtualScreen] — `GetSystemMetrics`, which reports the union of every
///   monitor, including the ones left of or above the primary.
/// * [topLevelWindows] / [windowAtPoint] — `EnumWindows`, `WindowFromPoint`
///   and the visibility/cloak checks that turn a raw handle list into
///   "windows a person could mean".
/// * [captureRect] / [captureWindow] — GDI `BitBlt` and `PrintWindow`, the
///   two calls that turn screen or window pixels into a bitmap.
///   `PrintWindow` is what makes window-mode capture work on an *occluded*
///   window, which copying the window's screen rect cannot do.
/// * [copyToClipboard] — `CF_DIB`, the clipboard format every Windows app
///   that pastes images actually reads; Flutter's `Clipboard` carries text
///   only.
/// * [setClickThrough] — `WS_EX_TRANSPARENT`, the one style a pinned image
///   needs that `window_manager` does not expose.

/// Whether this process is running on Windows, where all of this applies.
bool get isWindowsDesktop => Platform.isWindows;

/// The handler the window-enumeration trampoline delegates to.
///
/// `Pointer.fromFunction` only accepts a *static* Dart function — a closure
/// capturing state cannot cross into native code — so the two enumerations
/// below share one top-level trampoline and differ only in the handler they
/// install for the duration of the call. Single-threaded by construction:
/// the UI thread is the only caller and `EnumWindows` is synchronous.
bool Function(HWND hwnd)? _enumHandler;

int _enumWindowsProc(Pointer hwnd, int lparam) {
  final handler = _enumHandler;
  if (handler == null) return TRUE;
  return handler(HWND(hwnd)) ? TRUE : FALSE;
}

/// Runs [handler] over every top-level window via `EnumWindows`.
void _enumWindows(bool Function(HWND hwnd) handler) {
  _enumHandler = handler;
  try {
    EnumWindows(
      Pointer.fromFunction<WNDENUMPROC>(_enumWindowsProc, TRUE),
      LPARAM(0),
    );
  } finally {
    _enumHandler = null;
  }
}

/// The union of all monitors, in physical pixels; the origin can be
/// negative when a monitor sits left of or above the primary.
Rect virtualScreen() {
  return Rect.fromLTWH(
    GetSystemMetrics(SM_XVIRTUALSCREEN).toDouble(),
    GetSystemMetrics(SM_YVIRTUALSCREEN).toDouble(),
    GetSystemMetrics(SM_CXVIRTUALSCREEN).toDouble(),
    GetSystemMetrics(SM_CYVIRTUALSCREEN).toDouble(),
  );
}

/// The cursor's position in physical pixels.
Offset cursorPosition() {
  final point = calloc<POINT>();
  try {
    if (!GetCursorPos(point).value) return Offset.zero;
    return Offset(point.ref.x.toDouble(), point.ref.y.toDouble());
  } finally {
    calloc.free(point);
  }
}

/// A top-level window another application owns.
final class ForeignWindow {
  const ForeignWindow({
    required this.hwnd,
    required this.title,
    required this.bounds,
    required this.processId,
  });

  /// The window handle, as an int because Dart has no HWND type.
  final int hwnd;

  /// The window's caption, empty when it has none.
  final String title;

  /// The window's frame bounds in physical pixels.
  final Rect bounds;

  /// The process that owns it, so our own windows can be excluded.
  final int processId;
}

/// Every visible top-level window on the desktop that is not ours.
///
/// The filters are the difference between "windows" and "noise": invisible
/// windows, cloaked UWP hosts, tool windows, and this process's own windows
/// — the overlay itself must never be a capture candidate, or it would
/// screenshot itself.
List<ForeignWindow> topLevelWindows() {
  final self = GetCurrentProcessId();
  final found = <ForeignWindow>[];
  final procId = calloc<Uint32>();
  try {
    _enumWindows((handle) {
      if (!IsWindowVisible(handle)) return true;
      if (_isCloaked(handle)) return true;
      if (_isToolWindow(handle)) return true;
      GetWindowThreadProcessId(handle, procId);
      if (procId.value == self) return true;
      final candidate = _describe(handle, procId.value);
      if (candidate != null) found.add(candidate);
      return true;
    });
  } finally {
    calloc.free(procId);
  }
  return found;
}

/// The top-level window under [point], or null when the desktop itself —
/// or one of our own windows — is under it.
///
/// `WindowFromPoint` can answer a child control; walking to `GA_ROOT` gives
/// the window a person would recognise — the dialog, not its button.
ForeignWindow? windowAtPoint(Offset point) {
  final pt = calloc<POINT>();
  pt.ref.x = point.dx.round();
  pt.ref.y = point.dy.round();
  try {
    final hit = WindowFromPoint(pt.ref);
    if (hit.address == 0) return null;
    final root = GetAncestor(hit, GA_ROOT);
    final handle = root.address == 0 ? hit : root;
    if (!IsWindowVisible(handle) || _isCloaked(handle)) return null;
    final procId = calloc<Uint32>();
    try {
      GetWindowThreadProcessId(handle, procId);
      if (procId.value == GetCurrentProcessId()) return null;
      return _describe(handle, procId.value);
    } finally {
      calloc.free(procId);
    }
  } finally {
    calloc.free(pt);
  }
}

/// Reads [handle]'s bounds and caption into a [ForeignWindow], or null when
/// it has no usable frame.
ForeignWindow? _describe(HWND handle, int processId) {
  final rect = calloc<RECT>();
  try {
    if (!GetWindowRect(handle, rect).value) return null;
    final width = rect.ref.right - rect.ref.left;
    final height = rect.ref.bottom - rect.ref.top;
    if (width <= 0 || height <= 0) return null;
    return ForeignWindow(
      hwnd: handle.address,
      title: _windowTitle(handle),
      bounds: Rect.fromLTWH(
        rect.ref.left.toDouble(),
        rect.ref.top.toDouble(),
        width.toDouble(),
        height.toDouble(),
      ),
      processId: processId,
    );
  } finally {
    calloc.free(rect);
  }
}

/// Whether [hwnd] is cloaked — the state UWP apps and some suspended
/// windows sit in, where they are "visible" but draw nothing.
bool _isCloaked(HWND hwnd) {
  final value = calloc<DWORD>();
  try {
    DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, value.cast(), sizeOf<DWORD>());
    return value.value != 0;
  } finally {
    calloc.free(value);
  }
}

/// Whether [hwnd] is a tool window: small utility surfaces that are never
/// what a "capture this window" gesture means.
bool _isToolWindow(HWND hwnd) {
  final style = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
  if (style.error.isError) return false;
  return (style.value & WS_EX_TOOLWINDOW) != 0;
}

/// The window's caption, or empty when it has none or cannot be read.
String _windowTitle(HWND hwnd) {
  final length = GetWindowTextLength(hwnd);
  if (length.error.isError || length.value <= 0) return '';
  final buffer = calloc<Uint16>(length.value + 1);
  try {
    final read = GetWindowText(
      hwnd,
      PWSTR(buffer.cast<Utf16>()),
      length.value + 1,
    );
    if (read.error.isError || read.value <= 0) return '';
    return buffer.cast<Utf16>().toDartString(length: read.value);
  } finally {
    calloc.free(buffer);
  }
}

/// The pixels of [rect] — a physical-pixel screen rectangle — as PNG bytes.
///
/// `BitBlt` from the screen DC is the oldest capture there is and still the
/// right one for a region: it returns exactly what is composited on screen,
/// at whatever DPI the monitor runs.
Uint8List? captureRect(Rect rect) {
  final width = rect.width.round();
  final height = rect.height.round();
  if (width <= 0 || height <= 0) return null;
  final screen = GetDC(null);
  if (screen.address == 0) return null;
  final memory = CreateCompatibleDC(screen);
  final bitmap = CreateCompatibleBitmap(screen, width, height);
  final old = SelectObject(memory, HGDIOBJ(bitmap));
  try {
    final copied = BitBlt(
      memory,
      0,
      0,
      width,
      height,
      screen,
      rect.left.round(),
      rect.top.round(),
      SRCCOPY,
    );
    if (!copied.value) return null;
    return _bitmapToPng(memory, bitmap, width, height);
  } finally {
    SelectObject(memory, old);
    DeleteObject(HGDIOBJ(bitmap));
    DeleteDC(memory);
    ReleaseDC(null, screen);
  }
}

/// The pixels of the window [hwnd], as PNG bytes.
///
/// `PrintWindow` asks the window to paint itself into our bitmap rather than
/// copying what is on screen — which is what makes an *occluded* window
/// capturable, and why window mode does not just take the window's screen
/// rect. `PW_RENDERFULLCONTENT` (2) is the flag modern apps need to include
/// their DirectComposition content; without it `PrintWindow` returns black
/// for everything drawn that way, which on Windows 10+ is most apps.
Uint8List? captureWindow(int hwnd) {
  const renderFullContent = 2; // PW_RENDERFULLCONTENT
  final rect = calloc<RECT>();
  try {
    if (!GetWindowRect(_hwnd(hwnd), rect).value) return null;
    final width = rect.ref.right - rect.ref.left;
    final height = rect.ref.bottom - rect.ref.top;
    if (width <= 0 || height <= 0) return null;
    final screen = GetDC(null);
    final memory = CreateCompatibleDC(screen);
    final bitmap = CreateCompatibleBitmap(screen, width, height);
    final old = SelectObject(memory, HGDIOBJ(bitmap));
    try {
      final painted = PrintWindow(
        _hwnd(hwnd),
        memory,
        PRINT_WINDOW_FLAGS(renderFullContent),
      );
      if (!painted) return null;
      return _bitmapToPng(memory, bitmap, width, height);
    } finally {
      SelectObject(memory, old);
      DeleteObject(HGDIOBJ(bitmap));
      DeleteDC(memory);
      ReleaseDC(null, screen);
    }
  } finally {
    calloc.free(rect);
  }
}

/// Reads a 32-bit top-down DIB out of [bitmap] and encodes it as PNG.
Uint8List? _bitmapToPng(HDC memory, HBITMAP bitmap, int width, int height) {
  // A negative height asks for a top-down DIB, which is the row order every
  // decoder expects; bottom-up would need a flip per row.
  final header = calloc<BITMAPINFOHEADER>();
  header.ref.biSize = sizeOf<BITMAPINFOHEADER>();
  header.ref.biWidth = width;
  header.ref.biHeight = -height;
  header.ref.biPlanes = 1;
  header.ref.biBitCount = 32;
  header.ref.biCompression = BI_RGB;
  final pixels = calloc<Uint8>(width * height * 4);
  try {
    // BITMAPINFO is BITMAPINFOHEADER followed by a colour table GetDIBits
    // will not consult for a 32-bit image; the header's own allocation is
    // large enough to point at as one.
    final lines = GetDIBits(
      memory,
      bitmap,
      0,
      height,
      pixels,
      header.cast<BITMAPINFO>(),
      DIB_RGB_COLORS,
    );
    if (lines == 0) return null;
    // GDI hands back BGRA and leaves alpha undefined — usually zero, which
    // would make every pixel transparent. Build the RGRA buffer by hand so
    // both corrections happen in one pass.
    final bgra = pixels.asTypedList(width * height * 4);
    final rgba = Uint8List(width * height * 4);
    for (var i = 0; i < width * height; i++) {
      final src = i * 4;
      final dst = i * 4;
      rgba[dst] = bgra[src + 2];
      rgba[dst + 1] = bgra[src + 1];
      rgba[dst + 2] = bgra[src];
      rgba[dst + 3] = 0xFF;
    }
    final image = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: rgba.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    return Uint8List.fromList(img.encodePng(image));
  } finally {
    calloc.free(pixels);
    calloc.free(header);
  }
}

/// Writes [png] to the clipboard as `CF_DIB`.
///
/// `CF_DIB` rather than the newer `PNG` clipboard format because every app
/// that pastes images — Notepad, Paint, browsers, chat clients — reads DIB,
/// and PNG support is patchy. The DIB is the same BITMAPINFOHEADER-plus-
/// pixels layout `_bitmapToPng` reads back, built by hand: header, then
/// bottom-up BGRA rows.
bool copyToClipboard(Uint8List png) {
  final decoded = img.decodePng(png);
  if (decoded == null) return false;
  final width = decoded.width;
  final height = decoded.height;
  final rowSize = (width * 4 + 3) & ~3; // rows are 4-byte aligned
  final pixelBytes = rowSize * height;
  final dib = calloc<Uint8>(40 + pixelBytes);
  try {
    final view = dib.asTypedList(40 + pixelBytes);
    void put32(int offset, int value) {
      view[offset] = value & 0xFF;
      view[offset + 1] = (value >> 8) & 0xFF;
      view[offset + 2] = (value >> 16) & 0xFF;
      view[offset + 3] = (value >> 24) & 0xFF;
    }

    put32(0, 40); // biSize
    put32(4, width);
    put32(8, height); // positive: bottom-up
    view[12] = 1; // biPlanes
    view[13] = 0;
    view[14] = 32; // biBitCount
    view[15] = 0;
    put32(16, 0); // biCompression = BI_RGB
    put32(20, pixelBytes); // biSizeImage
    // biXPelsPerMeter / biYPelsPerMeter / biClrUsed / biClrImportant stay 0.

    for (var y = 0; y < height; y++) {
      // DIB rows run bottom-up; the source image runs top-down.
      final srcY = height - 1 - y;
      for (var x = 0; x < width; x++) {
        final src = decoded.getPixel(x, srcY);
        final dst = 40 + y * rowSize + x * 4;
        view[dst] = src.b.toInt();
        view[dst + 1] = src.g.toInt();
        view[dst + 2] = src.r.toInt();
        view[dst + 3] = 0xFF;
      }
    }

    if (!OpenClipboard(null).value) return false;
    try {
      if (!EmptyClipboard().value) return false;
      final allocated = GlobalAlloc(GMEM_MOVEABLE, 40 + pixelBytes);
      if (!allocated.value.isValid) return false;
      final locked = GlobalLock(allocated.value);
      if (locked.value.address == 0) {
        GlobalFree(allocated.value);
        return false;
      }
      try {
        locked.value.cast<Uint8>().asTypedList(40 + pixelBytes).setAll(0, view);
      } finally {
        GlobalUnlock(allocated.value);
      }
      final placed = SetClipboardData(CF_DIB, HANDLE(allocated.value));
      if (!placed.value.isValid) {
        GlobalFree(allocated.value);
        return false;
      }
      return true;
    } finally {
      CloseClipboard();
    }
  } finally {
    calloc.free(dib);
  }
}

/// Sets or clears click-through on [hwnd].
///
/// `WS_EX_TRANSPARENT` alone is not enough for a top-level window — hit
/// testing only honours it together with `WS_EX_LAYERED`, and a layered
/// window with no alpha set would paint nothing, so the alpha is pinned to
/// fully opaque. This is the same trio every "click-through overlay" recipe
/// ends at; `window_manager`'s `setIgnoreMouseEvents` cannot do it because
/// it only toggles the transparent bit and leaves the window unpaintable.

/// Finds a visible top-level window whose title is exactly [title], or null.
///
/// How a pin window finds its own HWND: every pin is an engine in the same
/// process, so the process id cannot tell them apart — but each one sets a
/// unique title, and the title is the one handle Windows gives us.
int? hwndForTitle(String title) {
  final needle = title.toLowerCase();
  final found = <int>[];
  _enumWindows((handle) {
    if (!IsWindowVisible(handle)) return true;
    final text = _windowTitle(handle);
    if (text.toLowerCase() == needle) found.add(handle.address);
    return true;
  });
  return found.isEmpty ? null : found.first;
}

/// An int window handle as the [HWND] the win32 bindings expect.
HWND _hwnd(int hwnd) => HWND(Pointer.fromAddress(hwnd));

void setClickThrough(int hwnd, bool enabled) {
  final handle = _hwnd(hwnd);
  final current = GetWindowLongPtr(handle, GWL_EXSTYLE);
  if (current.error.isError) return;
  var style = current.value;
  if (enabled) {
    style |= WS_EX_TRANSPARENT | WS_EX_LAYERED;
  } else {
    style &= ~(WS_EX_TRANSPARENT | WS_EX_LAYERED);
  }
  if (SetWindowLongPtr(handle, GWL_EXSTYLE, style).error.isError) return;
  // Re-assert the frame after an exstyle change, or the new hit-test region
  // does not take effect until something else moves the window.
  const swpNoMove = 0x0002;
  const swpNoSize = 0x0001;
  const swpNoZOrder = 0x0004;
  const swpFrameChanged = 0x0020;
  final rect = calloc<RECT>();
  try {
    if (!GetWindowRect(handle, rect).value) return;
    SetWindowPos(
      handle,
      null,
      rect.ref.left,
      rect.ref.top,
      rect.ref.right - rect.ref.left,
      rect.ref.bottom - rect.ref.top,
      SET_WINDOW_POS_FLAGS(
        swpNoMove | swpNoSize | swpNoZOrder | swpFrameChanged,
      ),
    );
    if (!enabled) {
      // Leaving click-through may strand a layered alpha; restore full
      // opacity so the window cannot go invisible.
      SetLayeredWindowAttributes(
        handle,
        COLORREF(0),
        255,
        LAYERED_WINDOW_ATTRIBUTES_FLAGS(0x02), // LWA_ALPHA
      );
    }
  } finally {
    calloc.free(rect);
  }
}
