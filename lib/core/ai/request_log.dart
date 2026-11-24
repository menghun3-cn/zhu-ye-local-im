import 'dart:convert';
import 'dart:io';

/// One finished request, as the routing view lists it.
///
/// Only requests that actually got an answer are recorded —a request that
/// failed on every member has no tokens or timings worth a row, and its
/// failure already shows up as a red node on the graph.
final class AiRequestRecord {
  const AiRequestRecord({
    required this.at,
    required this.model,
    this.servedBy,
    required this.durationMs,
    this.ttftMs,
    this.totalTokens,
    this.cachedTokens,
    this.completionTokens,
  });

  /// When the request started.
  final DateTime at;

  /// The model reference the caller asked for (`provider/model` or
  /// `group/<id>`).
  final String model;

  /// The concrete `provider/model` member that actually answered, when the
  /// router resolved one.
  final String? servedBy;

  /// Wall-clock time from request start to the last event.
  final int durationMs;

  /// Time to the first content token; null for non-streamed replies, which
  /// have no meaningful "first token" distinct from the whole answer.
  final int? ttftMs;

  final int? totalTokens;
  final int? cachedTokens;
  final int? completionTokens;

  Map<String, Object?> toJson() => {
    'at': at.toIso8601String(),
    'model': model,
    if (servedBy != null) 'served_by': servedBy,
    'duration_ms': durationMs,
    if (ttftMs != null) 'ttft_ms': ttftMs,
    if (totalTokens != null) 'total_tokens': totalTokens,
    if (cachedTokens != null) 'cached_tokens': cachedTokens,
    if (completionTokens != null) 'completion_tokens': completionTokens,
  };

  factory AiRequestRecord.fromJson(Map<String, Object?> json) {
    final at = DateTime.tryParse(json['at'] as String? ?? '');
    if (at == null) throw const FormatException('request record has no time');
    return AiRequestRecord(
      at: at,
      model: json['model'] as String? ?? '',
      servedBy: json['served_by'] as String?,
      durationMs: json['duration_ms'] as int? ?? 0,
      ttftMs: json['ttft_ms'] as int?,
      totalTokens: json['total_tokens'] as int?,
      cachedTokens: json['cached_tokens'] as int?,
      completionTokens: json['completion_tokens'] as int?,
    );
  }
}

/// A rolling file of recent requests —the routing view's "what just
/// happened" list.
///
/// Records older than [retention] are dropped on every write, and the whole
/// file is capped so a busy day cannot grow it without bound. Writes go
/// through a temp file + rename so a crash mid-write cannot leave a
/// half-parsed log.
final class AiRequestLog {
  AiRequestLog({required this.file, this.retention = const Duration(days: 7)});

  final File file;
  final Duration retention;

  /// Hard cap on kept records —the retention window is the real bound, this
  /// is the safety net for a pathological day.
  static const int maxRecords = 500;

  /// Bumped on every accepted [record]. Live views poll it instead of the
  /// file, the same trick [AiRuntime.configVersion] plays for settings.
  int _version = 0;
  int get version => _version;

  Future<List<AiRequestRecord>> load() async {
    if (!await file.exists()) return <AiRequestRecord>[];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return <AiRequestRecord>[];
      final records = <AiRequestRecord>[];
      for (final entry in decoded) {
        if (entry is! Map) continue;
        try {
          records.add(AiRequestRecord.fromJson(entry.cast<String, Object?>()));
        } on Object {
          // One malformed row must not hide the rest of the log.
        }
      }
      return records;
    } on Object {
      return <AiRequestRecord>[];
    }
  }

  /// Appends [record] and rewrites the file pruned to the retention window.
  ///
  /// Read-modify-write is not atomic against a concurrent writer, but the
  /// only writers are this app's own router calls, which serialize through
  /// the event loop closely enough for a diagnostic log.
  Future<void> record(AiRequestRecord record) async {
    _version++;
    // load() may hand back an unmodifiable empty list —copy before adding.
    final records = List<AiRequestRecord>.of(await load());
    records.add(record);
    final cutoff = DateTime.now().subtract(retention);
    records.removeWhere((r) => r.at.isBefore(cutoff));
    if (records.length > maxRecords) {
      records.removeRange(0, records.length - maxRecords);
    }
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode([for (final r in records) r.toJson()]));
    await tmp.rename(file.path);
  }
}
