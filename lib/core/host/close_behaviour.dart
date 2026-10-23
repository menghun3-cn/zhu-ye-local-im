/// What the window's close button does, on a platform that has a window.
///
/// Kept in the profile rather than in the window itself. The window is the one
/// thing that cannot remember a choice about what closing it should do: it is
/// gone by the time the choice would matter again. So the app remembers it, and
/// tells the host which one is in force — once as it starts, and again whenever
/// the user changes it.
enum CloseBehaviour {
  /// Closing the window ends the app.
  quit('quit'),

  /// Closing the window hides it and the app keeps running, reachable from the
  /// notification area. The default: what this product is for is being
  /// reachable, and an app that ends when its last window closes cannot receive
  /// anything.
  minimiseToTray('tray');

  const CloseBehaviour(this.wireName);

  /// How this value is spelled in the profile file.
  ///
  /// A name of its own rather than the Dart identifier or the index, because
  /// this is a file format: an index silently renumbers itself the day somebody
  /// reorders the enum, and an identifier is free to be renamed.
  final String wireName;

  /// Reads [name] back, or null when it is not one this build knows.
  ///
  /// Null rather than a throw, and the caller takes the default: this comes out
  /// of a file an older version wrote, and a value a *newer* version invented is
  /// not damage. An upgrade must not turn a profile into an error.
  static CloseBehaviour? fromWireName(String name) {
    for (final behaviour in values) {
      if (behaviour.wireName == name) return behaviour;
    }
    return null;
  }
}
