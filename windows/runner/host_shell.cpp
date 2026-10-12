#include "host_shell.h"

#include <shellapi.h>
#include <string.h>

#include <string>

#include "resource.h"
#include "win32_window.h"

// Nothing in this file is written in the characters the user sees, and nothing
// in it is non-ASCII. A non-ASCII byte here is warning C4819 -- the file cannot
// be read in code page 936 -- which this project's runner build promotes to a
// hard error, because the machine that builds it has that code page. So the
// few strings that reach the user are spelled as \uXXXX escapes; each one is
// annotated with what it says.

const char kHostChannelName[] = "cn.hnasct.local_transfer/host";

namespace {

// Keeps the process unique per signed-in session. The "Local\" namespace is
// deliberate: a second user, or a second remote session, running the
// application is a different and entirely legitimate instance.
constexpr const wchar_t kSingleInstanceMutex[] =
    L"Local\\cn.hnasct.local_transfer.instance";

// The per-user autostart entry, and the name it is stored under. The name is
// ASCII so that it is legible and stable in regedit regardless of the display
// language.
constexpr const wchar_t kRunKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr const wchar_t kRunValue[] = L"LocalTransfer";

constexpr const wchar_t kShowExistingMessageName[] =
    L"cn.hnasct.local_transfer.show-existing-instance";

constexpr UINT kTrayIconId = 1;

// Notification-area callbacks arrive as a window message of our own rather than
// as a mouse message, so the only requirement is that it is unique within this
// process.
constexpr UINT kTrayCallbackMessage = WM_APP + 1;

// Notification-area menu commands.
constexpr UINT kCommandShowWindow = 1;
constexpr UINT kCommandExit = 2;

// "zhuye LAN transfer" -- the notification-area tooltip.
constexpr const wchar_t kTrayTip[] =
    L"\u7af9\u53f6\u5c40\u57df\u7f51\u4f20\u8f93";
// "show main window"
constexpr const wchar_t kShowWindowText[] =
    L"\u663e\u793a\u4e3b\u7a97\u53e3";
// "exit"
constexpr const wchar_t kExitText[] = L"\u9000\u51fa";

// How long to keep looking for the already-running instance's window before
// giving up on raising it. Long enough to cover a second launch that lands
// during the first one's startup, where the window does not exist yet, and
// short enough that the duplicate process still leaves immediately.
constexpr int kRaiseAttempts = 20;
constexpr DWORD kRaiseIntervalMs = 100;

std::wstring CurrentExecutablePath() {
  std::wstring buffer(MAX_PATH, L'\0');
  for (;;) {
    const DWORD length = ::GetModuleFileNameW(
        nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
    if (length == 0) {
      return std::wstring();
    }
    // A truncated result fills the buffer exactly and is not terminated.
    if (length < buffer.size() - 1) {
      buffer.resize(length);
      return buffer;
    }
    buffer.resize(buffer.size() * 2);
  }
}

// Compares an autostart entry against the running executable. The entry is
// written quoted, because it is launched as a command line and the path
// routinely contains spaces; paths themselves are case-insensitive.
bool PointsAtThisExecutable(const std::wstring& entry) {
  std::wstring trimmed = entry;
  if (trimmed.size() >= 2 && trimmed.front() == L'"' && trimmed.back() == L'"') {
    trimmed = trimmed.substr(1, trimmed.size() - 2);
  }
  const std::wstring self = CurrentExecutablePath();
  if (self.empty() || trimmed.size() != self.size()) {
    return false;
  }
  return ::_wcsicmp(trimmed.c_str(), self.c_str()) == 0;
}

// The stored autostart entry, or an empty string when there is none or it is
// not a string. An entry pointing somewhere else is returned as it is, for
// PointsAtThisExecutable to reject.
std::wstring ReadAutostartEntry() {
  HKEY key = nullptr;
  if (::RegOpenKeyExW(HKEY_CURRENT_USER, kRunKey, 0, KEY_QUERY_VALUE, &key) !=
      ERROR_SUCCESS) {
    return std::wstring();
  }

  std::wstring entry;
  DWORD type = 0;
  DWORD size = 0;
  if (::RegQueryValueExW(key, kRunValue, nullptr, &type, nullptr, &size) ==
          ERROR_SUCCESS &&
      type == REG_SZ && size >= sizeof(wchar_t)) {
    entry.resize(size / sizeof(wchar_t));
    if (::RegQueryValueExW(key, kRunValue, nullptr, &type,
                           reinterpret_cast<BYTE*>(&entry[0]),
                           &size) != ERROR_SUCCESS) {
      entry.clear();
    } else {
      // |size| counts the terminator.
      entry.resize(::wcslen(entry.c_str()));
    }
  }
  ::RegCloseKey(key);
  return entry;
}

}  // namespace

HostShell::HostShell() {
  // The notification area wants a small icon, and it wants one at the size the
  // current DPI calls for rather than whatever sizes the .ico happens to hold.
  const int width = ::GetSystemMetrics(SM_CXSMICON);
  const int height = ::GetSystemMetrics(SM_CYSMICON);
  tray_icon_ = static_cast<HICON>(
      ::LoadImageW(::GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON),
                   IMAGE_ICON, width, height, LR_DEFAULTCOLOR));
  if (tray_icon_ == nullptr) {
    // An icon-less entry in the notification area is still better than an
    // application the user cannot get back to.
    tray_icon_ = ::LoadIconW(nullptr, IDI_APPLICATION);
  }
}

HostShell::~HostShell() {
  Detach();
  if (tray_icon_ != nullptr) {
    ::DestroyIcon(tray_icon_);
    tray_icon_ = nullptr;
  }
}

// static
UINT HostShell::ShowExistingMessage() {
  static const UINT message =
      ::RegisterWindowMessageW(kShowExistingMessageName);
  return message;
}

// static
UINT HostShell::TaskbarCreatedMessage() {
  // Broadcast by the shell when it starts, which is also when every
  // notification-area icon that was there before it was restarted is gone.
  static const UINT message = ::RegisterWindowMessageW(L"TaskbarCreated");
  return message;
}

// static
bool HostShell::AcquireSingleInstance() {
  // Held for the lifetime of the process and deliberately never released or
  // closed: the name has to stay taken for exactly as long as this instance
  // runs, and Windows drops it when the process ends either way.
  static HANDLE instance_mutex =
      ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutex);
  if (instance_mutex == nullptr) {
    // Cannot tell whether we are the first. Opening a second window is worse
    // than opening one that might be redundant, so carry on.
    return true;
  }
  if (::GetLastError() != ERROR_ALREADY_EXISTS) {
    return true;
  }

  for (int attempt = 0; attempt < kRaiseAttempts; ++attempt) {
    HWND existing = ::FindWindowW(kWin32WindowClassName, nullptr);
    if (existing != nullptr) {
      // Handing over the right to take the foreground is what makes this work:
      // without it the window is raised but stays behind whatever the user
      // clicked from, which reads as the second launch having done nothing.
      DWORD owner = 0;
      ::GetWindowThreadProcessId(existing, &owner);
      if (owner != 0) {
        ::AllowSetForegroundWindow(owner);
      }
      ::PostMessageW(existing, ShowExistingMessage(), 0, 0);
      return false;
    }
    ::Sleep(kRaiseIntervalMs);
  }
  return false;
}

void HostShell::Attach(HWND window) {
  window_ = window;
}

void HostShell::Detach() {
  RemoveTrayIcon();
  window_ = nullptr;
}

void HostShell::set_close_to_tray(bool value) {
  close_to_tray_ = value;
}

bool HostShell::autostart_enabled() const {
  return PointsAtThisExecutable(ReadAutostartEntry());
}

void HostShell::set_autostart(bool enabled) {
  HKEY key = nullptr;
  if (::RegCreateKeyExW(HKEY_CURRENT_USER, kRunKey, 0, nullptr,
                        REG_OPTION_NON_VOLATILE, KEY_SET_VALUE, nullptr, &key,
                        nullptr) != ERROR_SUCCESS) {
    return;
  }

  if (!enabled) {
    ::RegDeleteValueW(key, kRunValue);
    ::RegCloseKey(key);
    return;
  }

  const std::wstring path = CurrentExecutablePath();
  if (!path.empty()) {
    // Quoted, and rewritten on every enable, so that an entry left behind by an
    // earlier install or an older location is replaced rather than shadowed.
    const std::wstring command = L"\"" + path + L"\"";
    ::RegSetValueExW(
        key, kRunValue, 0, REG_SZ,
        reinterpret_cast<const BYTE*>(command.c_str()),
        static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
  }
  ::RegCloseKey(key);
}

void HostShell::AddTrayIcon() {
  if (tray_icon_added_ || window_ == nullptr) {
    return;
  }

  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(data);
  data.hWnd = window_;
  data.uID = kTrayIconId;
  data.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  data.uCallbackMessage = kTrayCallbackMessage;
  data.hIcon = tray_icon_;
  ::lstrcpynW(data.szTip, kTrayTip, ARRAYSIZE(data.szTip));

  if (::Shell_NotifyIconW(NIM_ADD, &data) != FALSE) {
    tray_icon_added_ = true;
  }
}

void HostShell::RemoveTrayIcon() {
  if (!tray_icon_added_ || window_ == nullptr) {
    // Nothing to take down, or nowhere to take it down from.
    tray_icon_added_ = false;
    return;
  }

  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(data);
  data.hWnd = window_;
  data.uID = kTrayIconId;
  ::Shell_NotifyIconW(NIM_DELETE, &data);
  tray_icon_added_ = false;
}

void HostShell::Activate() {
  if (window_ == nullptr) {
    return;
  }

  ::ShowWindow(window_, ::IsIconic(window_) ? SW_RESTORE : SW_SHOW);
  if (::SetForegroundWindow(window_) == FALSE) {
    // Windows routinely refuses this to a process the user did not just click
    // on. Flashing the taskbar button is the supported way of still saying
    // "this is over here".
    FLASHWINFO flash{};
    flash.cbSize = sizeof(flash);
    flash.hwnd = window_;
    flash.dwFlags = FLASHW_ALL;
    flash.uCount = 3;
    ::FlashWindowEx(&flash);
  }
}

void HostShell::ShowTrayMenu() {
  HMENU menu = ::CreatePopupMenu();
  if (menu == nullptr) {
    return;
  }
  ::AppendMenuW(menu, MF_STRING, kCommandShowWindow, kShowWindowText);
  ::AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  ::AppendMenuW(menu, MF_STRING, kCommandExit, kExitText);

  POINT cursor{};
  ::GetCursorPos(&cursor);
  // Without this the menu stays up when the user clicks somewhere else, which
  // is the single most common bug in a hand-rolled notification-area menu.
  ::SetForegroundWindow(window_);
  const UINT command =
      ::TrackPopupMenu(menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON,
                       cursor.x, cursor.y, 0, window_, nullptr);
  ::DestroyMenu(menu);
  ::PostMessageW(window_, WM_NULL, 0, 0);

  switch (command) {
    case kCommandShowWindow:
      Activate();
      break;
    case kCommandExit:
      QuitFromTray();
      break;
    default:
      break;
  }
}

void HostShell::HandleTrayMouse(LPARAM lparam) {
  switch (static_cast<UINT>(lparam)) {
    case WM_LBUTTONUP:
    case WM_LBUTTONDBLCLK:
      Activate();
      break;
    case WM_RBUTTONUP:
      ShowTrayMenu();
      break;
    default:
      break;
  }
}

void HostShell::QuitFromTray() {
  if (window_ == nullptr) {
    return;
  }
  // Sent as an ordinary close so the window is torn down the same way it would
  // be for a user who had chosen to quit rather than to minimise.
  close_to_tray_ = false;
  ::PostMessageW(window_, WM_CLOSE, 0, 0);
}

bool HostShell::HandleMessage(HWND window, UINT message, WPARAM wparam,
                              LPARAM lparam) {
  const UINT show_existing = ShowExistingMessage();
  if (show_existing != 0 && message == show_existing) {
    Activate();
    return true;
  }

  const UINT taskbar_created = TaskbarCreatedMessage();
  if (taskbar_created != 0 && message == taskbar_created) {
    // The shell restarted and took every notification-area icon with it. This
    // is the one moment they have to be put back.
    tray_icon_added_ = false;
    AddTrayIcon();
    return true;
  }

  if (message == kTrayCallbackMessage) {
    HandleTrayMouse(lparam);
    return true;
  }

  switch (message) {
    case WM_QUERYENDSESSION:
      // Never hold up a log-off or a restart, and never come back from one by
      // restoring a window into a session that is going away.
      close_to_tray_ = false;
      return false;

    case WM_CLOSE:
      if (!close_to_tray_) {
        return false;
      }
      AddTrayIcon();
      if (!tray_icon_added_) {
        // Hiding the window without an icon would strand the application
        // somewhere the user has no way of reaching, so refuse to.
        return false;
      }
      ::ShowWindow(window, SW_HIDE);
      return true;

    default:
      return false;
  }
}
