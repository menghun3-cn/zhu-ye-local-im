#ifndef RUNNER_HOST_SHELL_H_
#define RUNNER_HOST_SHELL_H_

#include <windows.h>

// The name of the method channel the Dart side reaches these behaviours
// through. Kept next to them so the two spellings cannot drift apart. Narrow
// rather than wide: a channel name is a Dart string, and the C++ wrapper takes
// it as one.
extern const char kHostChannelName[];

// The parts of "running as a desktop application" that Dart cannot ask for and
// that no plugin here provides: being the only copy of the application, owning
// a notification-area icon, deciding what the close button means, and starting
// with Windows.
//
// This is deliberately plain Win32 with no Flutter in it, so the message loop
// and the method channel can both drive the same object.
class HostShell {
 public:
  HostShell();
  ~HostShell();

  HostShell(const HostShell&) = delete;
  HostShell& operator=(const HostShell&) = delete;

  // Call once, before there is any window. Returns true when this process is
  // the first instance. When it is not, raises the window of the instance that
  // is and returns false, at which point the caller should exit without
  // creating one.
  static bool AcquireSingleInstance();

  // The window this shell speaks for. Until this is called nothing is shown in
  // the notification area and WM_CLOSE is left alone.
  void Attach(HWND window);

  // Takes the notification-area icon down. Called before the window goes away.
  void Detach();

  // True when WM_CLOSE should hide the window rather than end the process.
  void set_close_to_tray(bool value);

  // The per-user autostart entry. Nothing is cached on this side: the registry
  // is the only store, so an entry changed by hand reads back as it is.
  bool autostart_enabled() const;
  void set_autostart(bool enabled);

  // Returns true when |message| was consumed. WM_CLOSE is consumed exactly when
  // the window is meant to keep running in the notification area -- and, for
  // safety, exactly when there is an icon to bring it back with.
  bool HandleMessage(HWND window, UINT message, WPARAM wparam, LPARAM lparam);

 private:
  // Both are registered once per session. Either can be zero if registration
  // failed, which callers have to tolerate.
  static UINT ShowExistingMessage();
  static UINT TaskbarCreatedMessage();

  void AddTrayIcon();
  void RemoveTrayIcon();

  // Brings the window back and puts it in front of whatever the user is
  // currently looking at.
  void Activate();

  void ShowTrayMenu();
  void HandleTrayMouse(LPARAM lparam);
  void QuitFromTray();

  HWND window_ = nullptr;
  HICON tray_icon_ = nullptr;
  bool close_to_tray_ = true;
  bool tray_icon_added_ = false;
};

#endif  // RUNNER_HOST_SHELL_H_
