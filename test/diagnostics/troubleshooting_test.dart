import 'dart:convert';

import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

ProcessOutput out(int exitCode, [String stdout = '']) =>
    ProcessOutput(exitCode: exitCode, stdout: stdout);

void main() {
  group('port levels', () {
    test(
      'session on the well-known port is ok, fallback warns, absent errors',
      () {
        expect(sessionPortLevel(defaultSessionPort), CheckStatus.ok);
        expect(sessionPortLevel(51234), CheckStatus.warning);
        expect(sessionPortLevel(null), CheckStatus.error);
      },
    );

    test('pairing degrades to warning rather than error when absent', () {
      expect(pairingPortLevel(defaultPairingPort), CheckStatus.ok);
      expect(pairingPortLevel(51234), CheckStatus.warning);
      expect(pairingPortLevel(null), CheckStatus.warning);
    });
  });

  group('portSpecCovers', () {
    test('matches Any, single ports, ranges and comma lists', () {
      expect(portSpecCovers('Any', 47655), isTrue);
      expect(portSpecCovers('47655', 47655), isTrue);
      expect(portSpecCovers('47654-47656', 47655), isTrue);
      expect(portSpecCovers('80,47655', 47655), isTrue);
      expect(portSpecCovers('47654-47654', 47655), isFalse);
      expect(portSpecCovers('Teredo', 47655), isFalse);
      expect(portSpecCovers('', 47655), isFalse);
    });
  });

  group('ruleCovers', () {
    const ours = r'C:\Apps\LocalTransfer\LocalTransfer.exe';

    FirewallRule rule({
      String protocol = 'TCP',
      String localPort = 'Any',
      String program = '',
    }) => FirewallRule(
      protocol: protocol,
      localPort: localPort,
      profile: 'Any',
      program: program,
    );

    test('an unscoped allow rule covers the port', () {
      expect(ruleCovers(rule(localPort: '47655'), 'TCP', 47655, ours), isTrue);
    });

    test('a rule scoped to this program covers it', () {
      expect(
        ruleCovers(rule(localPort: '47655', program: ours), 'TCP', 47655, ours),
        isTrue,
      );
    });

    test('a rule scoped to another program does not', () {
      expect(
        ruleCovers(
          rule(localPort: '47655', program: r'C:\Other\app.exe'),
          'TCP',
          47655,
          ours,
        ),
        isFalse,
      );
    });

    test('protocol must match, with Any and the numeric forms counting', () {
      expect(
        ruleCovers(
          rule(protocol: 'UDP', localPort: '47655'),
          'TCP',
          47655,
          ours,
        ),
        isFalse,
      );
      expect(
        ruleCovers(
          rule(protocol: 'Any', localPort: '47655'),
          'TCP',
          47655,
          ours,
        ),
        isTrue,
      );
      expect(
        ruleCovers(rule(protocol: '6', localPort: '47655'), 'TCP', 47655, ours),
        isTrue,
      );
      expect(
        ruleCovers(
          rule(protocol: '17', localPort: '47654'),
          'UDP',
          47654,
          ours,
        ),
        isTrue,
      );
    });
  });

  group('profileApplies', () {
    test('matches the current category or Any, lenient when unknown', () {
      expect(profileApplies('Private', 'Private'), isTrue);
      expect(profileApplies('Private, Public', 'Public'), isTrue);
      expect(profileApplies('Private', 'Public'), isFalse);
      expect(profileApplies('Any', 'DomainAuthenticated'), isTrue);
      expect(profileApplies('Domain', 'DomainAuthenticated'), isTrue);
      expect(profileApplies('Private', null), isTrue);
    });
  });

  group('firewallReportFromSnapshot', () {
    const program = r'C:\Apps\LocalTransfer\LocalTransfer.exe';

    Map<String, Object?> payload({
      String category = 'Private',
      bool? enabled = true,
      List<Map<String, String>>? rules,
    }) => {
      'category': category,
      'enabled': enabled,
      'rules': rules ?? const [],
    };

    test('a disabled firewall reads open whatever the rules say', () {
      final report = firewallReportFromSnapshot(
        payload(enabled: false),
        programPath: program,
      );
      expect(report!.state, FirewallState.open);
    });

    test('full coverage reads open', () {
      final report = firewallReportFromSnapshot(
        payload(
          rules: const [
            {'proto': 'TCP', 'port': '47655,47656', 'prof': 'Any', 'prog': ''},
            {'proto': 'UDP', 'port': '47654', 'prof': 'Any', 'prog': ''},
          ],
        ),
        programPath: program,
      );
      expect(report!.state, FirewallState.open);
      expect(report.missing, isEmpty);
    });

    test('missing coverage names the ports', () {
      final report = firewallReportFromSnapshot(
        payload(
          rules: const [
            {'proto': 'TCP', 'port': '47655', 'prof': 'Any', 'prog': ''},
          ],
        ),
        programPath: program,
      );
      expect(report!.state, FirewallState.blocked);
      expect(report.missing, containsAll(['TCP 47656', 'UDP 47654']));
    });

    test('a rule for another program does not count', () {
      final report = firewallReportFromSnapshot(
        payload(
          rules: [
            for (final (proto, port) in requiredInboundPorts)
              {
                'proto': proto,
                'port': '$port',
                'prof': 'Any',
                'prog': r'C:\Other\app.exe',
              },
          ],
        ),
        programPath: program,
      );
      expect(report!.state, FirewallState.blocked);
      expect(report.missing, hasLength(3));
    });

    test('a service-scoped rule does not count', () {
      final report = firewallReportFromSnapshot(
        payload(
          rules: [
            for (final (proto, port) in requiredInboundPorts)
              {
                'proto': proto,
                'port': '$port',
                'prof': 'Any',
                'prog': '',
                'svc': 'SomeService',
              },
          ],
        ),
        programPath: program,
      );
      expect(report!.state, FirewallState.blocked);
      expect(report.missing, hasLength(3));
    });

    test('a rule on the wrong profile does not count', () {
      final report = firewallReportFromSnapshot(
        payload(
          category: 'Public',
          rules: const [
            {
              'proto': 'TCP',
              'port': '47655,47656',
              'prof': 'Private',
              'prog': '',
            },
            {'proto': 'UDP', 'port': '47654', 'prof': 'Private', 'prog': ''},
          ],
        ),
        programPath: program,
      );
      expect(report!.state, FirewallState.blocked);
    });

    test('COM-shaped values parse: numeric protocol and 47655 style ports', () {
      final report = firewallReportFromSnapshot(
        payload(
          rules: const [
            {
              'proto': '6',
              'port': '47655,47656',
              'prof': 'Private',
              'prog': program,
            },
            {
              'proto': '17',
              'port': '47654',
              'prof': 'Private',
              'prog': program,
            },
          ],
        ),
        programPath: program,
      );
      expect(report!.state, FirewallState.open);
    });

    test('malformed snapshots are null, not a guess', () {
      expect(
        firewallReportFromSnapshot('not a map', programPath: program),
        isNull,
      );
      expect(
        firewallReportFromSnapshot({'rules': 'oops'}, programPath: program),
        isNull,
      );
    });
  });

  group('openFirewallPorts', () {
    test('unsupported platforms never run a process', () async {
      var called = false;
      final result = await openFirewallPorts(
        platform: DevicePlatform.android,
        programPath: 'x',
        run: (exe, args) async {
          called = true;
          return out(0, '');
        },
      );
      expect(result, FirewallOpenResult.unsupported);
      expect(called, isFalse);
    });

    test('maps the elevated exit code to an outcome', () async {
      Future<FirewallOpenResult> withCode(int code) => openFirewallPorts(
        platform: DevicePlatform.windows,
        programPath: r'C:\Apps\LocalTransfer\LocalTransfer.exe',
        run: (exe, args) async => out(code, ''),
      );
      expect(await withCode(0), FirewallOpenResult.opened);
      expect(await withCode(3), FirewallOpenResult.cancelled);
      expect(await withCode(1), FirewallOpenResult.failed);
    });

    test(
      'the elevated script carries the program path and both rules',
      () async {
        String? captured;
        await openFirewallPorts(
          platform: DevicePlatform.windows,
          programPath: r'C:\Apps\LocalTransfer\LocalTransfer.exe',
          run: (exe, args) async {
            captured = args.last;
            return out(0, '');
          },
        );
        // The outer command hands the inner script over as -EncodedCommand;
        // decoding it is the only way to see what actually runs elevated.
        final encoded = RegExp(r"-EncodedCommand','([^']+)'")
            .firstMatch(captured!)!
            .group(1)!;
        final bytes = base64Decode(encoded);
        final inner = String.fromCharCodes([
          for (var i = 0; i + 1 < bytes.length; i += 2)
            bytes[i] | bytes[i + 1] << 8,
        ]);
        expect(inner, contains('New-NetFirewallRule'));
        expect(inner, contains(r'C:\Apps\LocalTransfer\LocalTransfer.exe'));
        expect(inner, contains('-Program'));
        expect(inner, contains('47655,47656'));
        expect(inner, contains('47654'));
      },
    );
  });
}
