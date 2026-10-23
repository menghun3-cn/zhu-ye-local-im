import 'dart:async';

/// The small part of the running host this app asks to change.
///
/// Three facts, all of them about the window the app is drawn in rather than
/// about the network or the user's Device: what its close button does, and
/// whether it starts with the system. A platform that has no window and no
/// notification area is not a broken host — it is a host with nothing here to
/// offer, and the surface that shows these settings is absent rather than
/// disabled. See `HostResolution.controlsWindow`, which is where that is
/// decided.
///
/// Deliberately narrow rather than one "platform services" facade that grows a
/// method per feature: a facade like that makes every new capability a change
/// to a type that everything already depends on.
abstract interface class HostShell {
  /// Whether the native window currently has the user's attention.
  ///
  /// The stream begins empty and emits on native activation changes. A host
  /// with no window leaves it empty; the shell treats that as an active window
  /// so it does not invent a notification state.
  Stream<bool> get windowActivity;

  /// Shows or clears the host's unread marker.
  ///
  /// Windows draws this as a red dot over the taskbar icon. A host without a
  /// notification area accepts the call and does nothing.
  Future<void> setUnread(bool value);

  /// Makes [value] true of the window's close button from now on.
  ///
  /// True means closing the window hides it and the app keeps running; false
  /// means closing it ends the app. Nothing is returned because nothing here is
  /// worth a round trip: the value came from the profile, which is what a
  /// restart reads, so the host's copy is a projection and cannot disagree for
  /// longer than the process lives.
  Future<void> setCloseToTray(bool value);

  /// Whether this app starts with the system.
  ///
  /// Asked rather than remembered by the app: the operating system holds the
  /// entry, so this one call answers both "did my write take" and "is it still
  /// true after the user removed it by hand". A cached copy could answer
  /// neither — it would be a switch that describes what the user pressed
  /// instead of what will happen.
  Future<bool> autostartEnabled();

  /// Makes [enabled] true of starting with the system.
  Future<void> setAutostart(bool enabled);
}
