#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <algorithm>
#include <vector>

#include "flutter_window.h"
#include "host_shell.h"
#include "utils.h"

// The flag that says this start is the last step of an update: a newer build
// has been unpacked beside the one it replaces, and this copy was started to
// finish putting it in place rather than to run. Spelled the same in
// `lib/ui/update_install.dart`, which is where the two folders it is given are
// read. The copy that finishes the update runs with the flag and draws
// nothing; the updated build it starts is the window the user asked for.
constexpr char kApplyUpdateFlag[] = "--apply-update";

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Read first: what kind of start this is decides the two things below, and
  // the arguments go to Dart afterwards either way.
  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();
  const bool applying_update =
      std::find(command_line_arguments.begin(), command_line_arguments.end(),
                kApplyUpdateFlag) != command_line_arguments.end();

  // A second copy of the application is not a second application: it hands the
  // focus to the copy that is already running and goes away. Checked before COM
  // or any window is set up, so the duplicate costs nothing and cannot be seen.
  // Skipped while an update is being finished, whose whole job is to run while
  // the copy it replaces is on its way out.
  if (!applying_update && !HostShell::AcquireSingleInstance()) {
    return EXIT_SUCCESS;
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  // The title bar. Spelled as escapes rather than as the characters themselves
  // on purpose, and ASCII-only: this file's encoding is whatever the toolchain
  // on this machine assumes it is, and a non-ASCII byte in it is warning C4819
  // (the file cannot be read in code page 936) -- which the runner's own build
  // promotes to a hard error. So the title itself is escaped below, and nothing
  // here is written in the characters it names.
  // `\u7af9\u53f6` is zhuye, the rest is "LAN transfer".
  if (!window.Create(L"\u7af9\u53f6\u5c40\u57df\u7f51\u4f20\u8f93", origin,
                     size)) {
    return EXIT_FAILURE;
  }
  // Not while an update is being finished: the copy that step makes is a whole
  // application, and a click that ended this process halfway through would
  // leave the folder holding half of each build. The updated build is the
  // window the user asked for, and the failure that update cannot draw is left
  // in the report file.
  window.SetQuitOnClose(!applying_update);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
