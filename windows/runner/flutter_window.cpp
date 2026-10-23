#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  host_shell_.Attach(GetHandle());
  host_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kHostChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  host_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) { HandleHostMethodCall(call, std::move(result)); });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  // Before anything else: the notification-area icon refers to this window and
  // has to be gone by the time the window is.
  host_shell_.Detach();

  if (host_channel_) {
    host_channel_ = nullptr;
  }

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::HandleHostMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();

  if (method == "setCloseToTray") {
    const bool* value = std::get_if<bool>(call.arguments());
    if (value == nullptr) {
      result->Error("bad_arguments", "setCloseToTray expects a bool");
      return;
    }
    host_shell_.set_close_to_tray(*value);
    result->Success();
    return;
  }

  if (method == "autostartEnabled") {
    result->Success(
        flutter::EncodableValue(host_shell_.autostart_enabled()));
    return;
  }

  if (method == "setAutostart") {
    const bool* value = std::get_if<bool>(call.arguments());
    if (value == nullptr) {
      result->Error("bad_arguments", "setAutostart expects a bool");
      return;
    }
    host_shell_.set_autostart(*value);
    result->Success();
    return;
  }

  if (method == "setUnread") {
    const bool* value = std::get_if<bool>(call.arguments());
    if (value == nullptr) {
      result->Error("bad_arguments", "setUnread expects a bool");
      return;
    }
    host_shell_.set_unread(*value);
    result->Success();
    return;
  }

  result->NotImplemented();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // The host's own behaviour gets first refusal, and for a reason: a window that
  // has been closed to the notification area is hidden, not closed, and the
  // framework must not be told that a close happened when it did not.
  if (host_shell_.HandleMessage(hwnd, message, wparam, lparam)) {
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_ACTIVATE: {
      const bool active = LOWORD(wparam) != WA_INACTIVE;
      if (active) {
        // The taskbar marker is about a window the user is not looking at.
        // Clearing it here happens in the same message that gives the window
        // focus, rather than after a round trip through Dart.
        host_shell_.set_unread(false);
      }
      if (host_channel_) {
        host_channel_->InvokeMethod(
            "windowActive",
            std::make_unique<flutter::EncodableValue>(active));
      }
      break;
    }
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
