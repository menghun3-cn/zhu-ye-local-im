/// How often this Device asks GitHub whether a newer build has been published.
///
/// Kept in the profile rather than in the layer that runs the timer: the
/// question "how often may the app reach out" is a preference about this
/// Device, and a preference belongs where the rest of them live — it has to
/// outlive the process to be read the first morning a user starts the app.
/// The UI reads and writes it through the controller, exactly like
/// [CloseBehaviour].
enum UpdateCheckInterval {
  /// Never asks again after the one startup question.
  off('off'),

  /// Asks again once an hour at most.
  hourly('hourly'),

  /// Asks again once every six hours at most.
  everySixHours('six-hours'),

  /// Asks again once a day at most.
  daily('daily'),

  /// Asks again once every three days at most.
  everyThreeDays('three-days');

  const UpdateCheckInterval(this.wireName);

  /// How this value is spelled in the profile file.
  ///
  /// A name of its own rather than the Dart identifier or the index, for the
  /// same reason [CloseBehaviour.wireName] has one: this is a file format, and
  /// an index silently renumbers itself the day somebody reorders the enum.
  final String wireName;

  /// Reads [name] back, or null when it is not one this build knows.
  ///
  /// Null rather than a throw, and the caller takes the default: this comes
  /// out of a file an older version wrote, and a value a *newer* version
  /// invented is not damage.
  static UpdateCheckInterval? fromWireName(String name) {
    for (final interval in values) {
      if (interval.wireName == name) return interval;
    }
    return null;
  }

  /// How long one interval is, or null for [off].
  Duration? get duration => switch (this) {
    off => null,
    hourly => const Duration(hours: 1),
    everySixHours => const Duration(hours: 6),
    daily => const Duration(hours: 24),
    everyThreeDays => const Duration(hours: 72),
  };
}
