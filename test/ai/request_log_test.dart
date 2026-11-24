import 'dart:convert';
import 'dart:io';

import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late AiRequestLog log;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ai-request-log-test');
    log = AiRequestLog(file: File('${dir.path}/requests.json'));
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  AiRequestRecord record({
    DateTime? at,
    String model = 'a/m1',
    int durationMs = 1200,
    int? ttftMs = 300,
    int? totalTokens = 800,
    int? cachedTokens = 100,
    int? completionTokens = 50,
  }) => AiRequestRecord(
    at: at ?? DateTime.now(),
    model: model,
    servedBy: 'a/m1',
    durationMs: durationMs,
    ttftMs: ttftMs,
    totalTokens: totalTokens,
    cachedTokens: cachedTokens,
    completionTokens: completionTokens,
  );

  test('records round-trip through the file', () async {
    await log.record(record());
    final records = await log.load();
    expect(records, hasLength(1));
    expect(records.single.model, 'a/m1');
    expect(records.single.servedBy, 'a/m1');
    expect(records.single.totalTokens, 800);
    expect(records.single.cachedTokens, 100);
    expect(records.single.completionTokens, 50);
    expect(records.single.ttftMs, 300);
  });

  test('version bumps on every accepted record', () async {
    final before = log.version;
    await log.record(record());
    await log.record(record(model: 'b/m2'));
    expect(log.version, before + 2);
  });

  test('records older than the retention window are pruned', () async {
    await log.record(
      record(at: DateTime.now().subtract(const Duration(days: 8))),
    );
    await log.record(record());
    final records = await log.load();
    expect(records, hasLength(1));
    expect(records.single.model, 'a/m1');
  });

  test('a corrupt file reads as empty rather than throwing', () async {
    await log.file.writeAsString('{not json');
    expect(await log.load(), isEmpty);
  });

  test('a malformed row does not hide the rest of the log', () async {
    await log.file.writeAsString(
      jsonEncode([
        {'bogus': true},
        record().toJson(),
      ]),
    );
    final records = await log.load();
    expect(records, hasLength(1));
  });

  test('the file is capped at maxRecords', () async {
    for (var i = 0; i < AiRequestLog.maxRecords + 5; i++) {
      await log.record(record(model: 'a/m$i'));
    }
    final records = await log.load();
    expect(records, hasLength(AiRequestLog.maxRecords));
  });
}
