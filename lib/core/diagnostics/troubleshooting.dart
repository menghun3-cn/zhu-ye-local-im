import 'dart:convert';
import 'dart:io';

import '../clipboard/clipboard_capability.dart';
import '../discovery/beacon.dart' as beacon;
import '../pairing/pairing_service.dart';
import '../session/link_manager.dart';

/// What one run of an external program produced.
///
/// A record of the three fields the diagnostics read rather than [ProcessResult]
/// itself: that class is `final` and cannot be stood in for, and a test double
/// is the whole reason this type exists.
final class ProcessOutput {
  const ProcessOutput({
    required this.exitCode,
    required this.stdout,
    this.stderr = '',
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

/// Runs one external program and answers with its result.
///
/// The seam exists for the same reason `Revealer` does: the firewall
/// diagnostics shell out to PowerShell, and a widget or `dart test` run that
/// drove the real thing would pop UAC prompts or depend on the rules of
/// whatever machine the suite happens to be on. Production leaves the field
/// alone and gets [Process.run].
typedef ProcessRunner = Future<ProcessOutput> Function(
  String executable,
  List<String> arguments,
);

/// Which process runner the diagnostics use.
///
/// A mutable field rather than a constructor argument, for the same reason
/// `RevealResolution` is one: the page that offers the checks is rebuilt often,
/// and a test-only parameter threaded through it would put the seam in the
/// application's vocabulary.
abstract final class DiagnosticsResolution {
  /// The runner in force. Set by a test; never by the application.
  static ProcessRunner runner = _runProcess;

  /// Restores [Process.run]. Called from a `tearDown`.
  static void reset() => runner = _runProcess;
}

Future<ProcessOutput> _runProcess(
  String executable,
  List<String> arguments,
) async {
  final result = await Process.run(executable, arguments);
  return ProcessOutput(
    exitCode: result.exitCode,
    stdout: '${result.stdout}',
    stderr: '${result.stderr}',
  );
}

/// How a diagnostic reads on the page.
///
/// `unknown` is "the check ran but could not answer" and `unsupported` is "the
/// check does not apply here" — neither is a failure, and the page shows both
/// quietly rather than as problems.
enum CheckStatus { ok, warning, error, unknown, unsupported, checking }

/// The ports this Device is actually listening on.
///
/// The well-known ports are *preferences*, not requirements — when the
/// operating system refuses one, the listener falls back to any free port and
/// Discovery advertises the real one. That fallback is why this report carries
/// the bound port rather than a boolean: "serving, but not on 47655" is a
/// different answer from "not serving at all", and only the first still lets
/// peers find this Device.
final class PortReport {
  const PortReport({
    required this.sessionPort,
    required this.pairingPort,
    this.discoveryPort = beacon.discoveryPort,
  });

  /// The port Sessions are accepted on, or null when not serving.
  final int? sessionPort;

  /// The port automatic Pairing attempts are answered on, or null.
  final int? pairingPort;

  /// The UDP port beacons are exchanged on. Bound at startup — a Device that
  /// could not take [discoveryPort] never got far enough to show this page.
  final int discoveryPort;
}

/// Whether the Session listener is healthy.
///
/// [ok] on the well-known port, [warning] when it fell back to another port —
/// peers still reach it through Discovery, but a peer dialled by bare address
/// on 47655 will not — and [error] when nothing is listening.
CheckStatus sessionPortLevel(int? port) {
  if (port == null) return CheckStatus.error;
  return port == defaultSessionPort ? CheckStatus.ok : CheckStatus.warning;
}

/// Whether the Pairing listener is healthy.
///
/// Weaker than the Session verdict for the same reason the controller treats
/// it as degraded rather than broken: this Device can still pair by dialling
/// out, so a missing listener is a [warning], not an [error].
CheckStatus pairingPortLevel(int? port) {
  if (port == null) return CheckStatus.warning;
  return port == defaultPairingPort ? CheckStatus.ok : CheckStatus.warning;
}

/// Whether inbound traffic can reach the ports at all.
enum FirewallState {
  /// Every needed port is covered by an inbound allow rule for this program.
  open,

  /// At least one needed port has no covering rule.
  blocked,

  /// The question could not be answered — the query failed, or the output was
  /// not understood.
  unknown,

  /// This platform has no Windows Firewall to ask about.
  unsupported,
}

/// What the firewall check found.
final class FirewallReport {
  const FirewallReport(this.state, {this.missing = const []});

  final FirewallState state;

  /// The ports no covering inbound allow rule was found for, spelled
  /// `TCP 47655` / `UDP 47654`, for the page's detail line.
  final List<String> missing;
}

/// One inbound allow rule, as the platform's firewall store reports it.
final class FirewallRule {
  const FirewallRule({
    required this.protocol,
    required this.localPort,
    required this.profile,
    required this.program,
    this.service = '',
  });

  /// `TCP`, `UDP`, `Any`, or a protocol number.
  final String protocol;

  /// The LocalPort filter: `Any`, a port, a range, or a comma list.
  final String localPort;

  /// The Profile filter, e.g. `Any` or `Private, Public`.
  final String profile;

  /// The Program filter, or empty when the rule applies to every program.
  final String program;

  /// The Service filter, or empty when the rule is not scoped to a service.
  ///
  /// A service-scoped rule admits one Windows service, not an ordinary
  /// executable, so it can never cover this app.
  final String service;
}

/// The (protocol, port) pairs a peer needs to reach this Device.
const List<(String, int)> requiredInboundPorts = [
  ('TCP', defaultSessionPort),
  ('TCP', defaultPairingPort),
  ('UDP', beacon.discoveryPort),
];

/// Whether [spec] — a Windows LocalPort filter value — covers [port].
///
/// The filter accepts `Any`, single ports, `a-b` ranges and comma-separated
/// mixes of both. Anything that is not a number (`RPC`, `Teredo`, service
/// names) cannot cover an unprivileged high port and is ignored rather than
/// guessed at.
bool portSpecCovers(String spec, int port) {
  if (spec.trim().toUpperCase() == 'ANY') return true;
  for (final part in spec.split(',')) {
    final token = part.trim();
    if (token.isEmpty) continue;
    final range = token.split('-');
    if (range.length == 2) {
      final low = int.tryParse(range[0].trim());
      final high = int.tryParse(range[1].trim());
      if (low != null && high != null && port >= low && port <= high) {
        return true;
      }
      continue;
    }
    if (int.tryParse(token) == port) return true;
  }
  return false;
}

/// Whether [rule] lets this Device's own process receive on (protocol, port).
///
/// A rule scoped to a *different* program does not count: Windows' own
/// "allow this app" prompt writes exactly that shape, so reading only the port
/// would call a firewall that blocks this app "open".
bool ruleCovers(
  FirewallRule rule,
  String protocol,
  int port,
  String programPath,
) {
  final ruleProto = rule.protocol.toUpperCase();
  final protoMatches =
      ruleProto == 'ANY' ||
      // COM reports "any protocol" as 0 or 256 depending on the rule's age.
      ruleProto == '0' ||
      ruleProto == '256' ||
      ruleProto == protocol ||
      (protocol == 'TCP' && ruleProto == '6') ||
      (protocol == 'UDP' && ruleProto == '17');
  if (!protoMatches || !portSpecCovers(rule.localPort, port)) return false;
  if (rule.service.trim().isNotEmpty) return false;
  final ruleProgram = rule.program.trim();
  if (ruleProgram.isEmpty ||
      ruleProgram.toUpperCase() == 'ANY' ||
      ruleProgram.toUpperCase() == '%PROGRAMFILES%\\*') {
    return true;
  }
  return ruleProgram.toLowerCase() == programPath.toLowerCase();
}

/// Whether [profileSpec] — a rule's Profile filter — applies on a machine whose
/// current network category is [category].
///
/// [category] is the `NetworkCategory` string (`Private`, `Public`,
/// `DomainAuthenticated`), or null when it could not be determined — in which
/// case any profile is accepted, because there is no honest way to narrow it.
bool profileApplies(String profileSpec, String? category) {
  final wanted = switch (category) {
    'Private' => 'PRIVATE',
    'Public' => 'PUBLIC',
    'DomainAuthenticated' => 'DOMAIN',
    _ => null,
  };
  if (wanted == null) return true;
  final profiles = profileSpec.toUpperCase();
  return profiles.contains('ANY') ||
      profiles.split(',').map((p) => p.trim()).contains(wanted);
}

/// Judges the rule set against [requiredInboundPorts].
///
/// Pure, so the parsing decisions — which are the part that can be wrong — are
/// exercised without PowerShell anywhere near them.
FirewallReport evaluateFirewallRules({
  required String? category,
  required bool? firewallEnabled,
  required List<FirewallRule> rules,
  required String programPath,
}) {
  // A disabled firewall blocks nothing, whatever the rules say.
  if (firewallEnabled == false) return const FirewallReport(FirewallState.open);
  final missing = <String>[];
  for (final (protocol, port) in requiredInboundPorts) {
    final covered = rules.any(
      (rule) =>
          profileApplies(rule.profile, category) &&
          ruleCovers(rule, protocol, port, programPath),
    );
    if (!covered) missing.add('$protocol $port');
  }
  return FirewallReport(
    missing.isEmpty ? FirewallState.open : FirewallState.blocked,
    missing: List.unmodifiable(missing),
  );
}

/// Judges a firewall snapshot against [requiredInboundPorts].
///
/// The snapshot is the decoded map the Windows runner's firewall channel
/// answers with: `category` (the current network's profile name), `enabled`
/// (whether that profile's firewall is on), and `rules` — each an inbound
/// allow rule carrying `proto`, `port`, `prof`, `prog` and `svc`.
///
/// Pure, so the parsing decisions — which are the part that can be wrong — are
/// exercised without a runner anywhere near them. Returns null on anything
/// unexpected, because the caller's answer to "I could not understand this" is
/// `unknown`, not a guess.
FirewallReport? firewallReportFromSnapshot(
  Object? snapshot, {
  required String programPath,
}) {
  if (snapshot is! Map) return null;
  final category = snapshot['category'];
  final enabled = snapshot['enabled'];
  final rawRules = snapshot['rules'];
  if (rawRules != null && rawRules is! List) return null;
  final rules = <FirewallRule>[
    if (rawRules is List)
      for (final entry in rawRules)
        if (entry is Map &&
            entry['proto'] is String &&
            entry['port'] is String &&
            entry['prof'] is String)
          FirewallRule(
            protocol: entry['proto'] as String,
            localPort: entry['port'] as String,
            profile: entry['prof'] as String,
            program: entry['prog'] is String ? entry['prog'] as String : '',
            service: entry['svc'] is String ? entry['svc'] as String : '',
          ),
  ];
  return evaluateFirewallRules(
    category: category is String && category.isNotEmpty ? category : null,
    firewallEnabled: enabled is bool ? enabled : null,
    rules: rules,
    programPath: programPath,
  );
}

/// UTF-16LE bytes, which is what `powershell -EncodedCommand` decodes.
///
/// `dart:convert` ships no UTF-16 codec, and the encoding is two bytes per
/// code unit with the low byte first — surrogate pairs pass through as their
/// two code units, which is exactly what the codec expects.
List<int> _utf16LittleEndian(String text) {
  final bytes = <int>[];
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    bytes.add(unit & 0xFF);
    bytes.add(unit >> 8);
  }
  return bytes;
}

/// The non-loopback IPv4 interfaces this machine currently has.
///
/// An empty answer means "no usable network" rather than "the enumeration
/// failed": both arrive the same way to the page, and both mean discovery has
/// nothing to announce on.
Future<List<NetworkInterface>> usableInterfaces() async {
  try {
    return await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
  } on Object {
    return const [];
  }
}

/// Interface-name fragments that suggest a VPN or tunnel adapter.
///
/// A heuristic, not a detection: the names are whatever the driver called the
/// adapter, and the list can only ever be a hint — which is why the page
/// reports it as a warning with the names attached rather than as a verdict.
/// `tailscale` is deliberately absent: this app has a first-class Tailscale
/// path, so its adapter is a feature, not interference.
const List<String> tunnelInterfaceMarkers = [
  'tap',
  'tun',
  'wintun',
  'wireguard',
  'openvpn',
  'zerotier',
  'fortinet',
  'globalprotect',
  'anyconnect',
  'ppp',
  'vpn',
];

/// The names of interfaces that look like VPN or tunnel adapters.
Future<List<String>> suspectedTunnelInterfaces() async {
  final interfaces = await usableInterfaces();
  return [
    for (final interface in interfaces)
      if (tunnelInterfaceMarkers.any(
        (marker) => interface.name.toLowerCase().contains(marker),
      ))
        interface.name,
  ];
}

/// What happened when the page asked for the ports to be opened.
enum FirewallOpenResult { opened, cancelled, failed, unsupported }

/// The script the elevated half runs.
///
/// `-Program` scopes each rule to this app's executable rather than opening
/// the ports to every program on the machine: an unscoped port rule would let
/// anything on the LAN — or anything else running here — use them. The two
/// rule names are also how [openFirewallPorts] stays idempotent: existing
/// rules with either name are removed first, so a moved executable updates
/// the rule instead of accumulating a stale one beside it.
String firewallOpenScript(String programPath) {
  if (programPath.contains("'")) {
    throw ArgumentError('program path may not contain a single quote');
  }
  return '''
Get-NetFirewallRule -DisplayName 'LocalTransfer','LocalTransfer Discovery' -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName 'LocalTransfer' -Direction Inbound -Action Allow -Program '$programPath' -Protocol TCP -LocalPort '47655,47656' | Out-Null
New-NetFirewallRule -DisplayName 'LocalTransfer Discovery' -Direction Inbound -Action Allow -Program '$programPath' -Protocol UDP -LocalPort '47654' | Out-Null
''';
}

/// Adds the inbound allow rules, asking for elevation first.
///
/// Windows Firewall changes need an administrator, and there is no way around
/// the UAC prompt — so "one click" is one click plus one consent dialog. The
/// elevated half is handed to PowerShell as `-EncodedCommand` (Base64 of
/// UTF-16LE) rather than as nested quoted arguments, which is the one encoding
/// that survives being wrapped in `Start-Process -ArgumentList` intact.
///
/// Exit codes: 0 opened, 3 the user declined the UAC prompt, anything else
/// failed. The code travels back through `Start-Process -PassThru`.
Future<FirewallOpenResult> openFirewallPorts({
  required DevicePlatform platform,
  required String programPath,
  ProcessRunner? run,
}) async {
  if (platform != DevicePlatform.windows) {
    return FirewallOpenResult.unsupported;
  }
  final String inner;
  try {
    inner = firewallOpenScript(programPath);
  } on ArgumentError {
    return FirewallOpenResult.failed;
  }
  final encoded = base64Encode(_utf16LittleEndian(inner));
  final outer =
      'try { '
      '\$p = Start-Process -FilePath powershell.exe -Verb RunAs -Wait -PassThru '
      '-WindowStyle Hidden -ArgumentList '
      "'-NoProfile','-EncodedCommand','$encoded'; "
      'exit \$p.ExitCode } catch { exit 3 }';
  final ProcessOutput result;
  try {
    result = await (run ?? DiagnosticsResolution.runner)('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      outer,
    ]);
  } on Object {
    return FirewallOpenResult.failed;
  }
  return switch (result.exitCode) {
    0 => FirewallOpenResult.opened,
    3 => FirewallOpenResult.cancelled,
    _ => FirewallOpenResult.failed,
  };
}
