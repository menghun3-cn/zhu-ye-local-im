/// The emoticons the composer can send, and the very small amount of state
/// around them.
///
/// Pure Dart on purpose: this is what a bubble renders, so the rendering
/// layer must be able to build it without pulling Flutter into `lib/core`.
library;

export 'emoji_table.dart';
export 'recent_emoji_store.dart';
