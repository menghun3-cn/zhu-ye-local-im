import 'dart:async';
import 'dart:convert';

/// One SSE frame: the optional `event:` name and the `data:` payload.
final class SseEvent {
  const SseEvent({this.event, required this.data});

  final String? event;
  final String data;
}

/// Parses a `text/event-stream` byte stream into frames.
///
/// SSE frames are separated by blank lines and a frame may carry several
/// `data:` lines that join with `\n`. Multi-byte UTF-8 characters can straddle
/// chunk boundaries, so decoding goes through [utf8.decoder] rather than a
/// per-chunk `utf8.decode` that would throw or mangle at the seam.
///
/// Comment lines (`:`-prefixed, including keep-alives) and unknown fields are
/// skipped. `[DONE]` is *not* special here — each codec decides what its
/// terminator looks like, because OpenAI's literal `[DONE]` is meaningless to
/// Anthropic and Gemini.
Stream<SseEvent> parseSse(Stream<List<int>> bytes) async* {
  String? event;
  final data = StringBuffer();
  var hasData = false;

  await for (final line
      in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.isEmpty) {
      if (hasData) {
        yield SseEvent(event: event, data: data.toString());
      }
      event = null;
      data.clear();
      hasData = false;
      continue;
    }
    if (line.startsWith(':')) continue;
    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    switch (field) {
      case 'event':
        event = value;
      case 'data':
        if (hasData) data.write('\n');
        data.write(value);
        hasData = true;
      default:
        break;
    }
  }
  if (hasData) {
    yield SseEvent(event: event, data: data.toString());
  }
}
