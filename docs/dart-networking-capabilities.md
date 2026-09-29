# Dart Networking & TLS Capabilities

Verified against the official Dart API docs (`api.dart.dev/stable`, Dart
3.13.4) on 2026-09-29. Facts only.

## Interface enumeration — subnet info IS available

`NetworkInterface.list({includeLoopback, includeLinkLocal, type})` returns
`List<NetworkInterface>`; each has only `addresses`, `index`, and `name`.

But the objects inside `addresses` are **`InterfaceAddress`**, not
`InternetAddress`, and `InterfaceAddress` extends `InternetAddress` with:

- **`prefixLength → int`** — "The prefix length of the network, also known as
  the subnet mask length."
- **`broadcast → InternetAddress?`** — "The broadcast address of this
  network." (IPv4 only)

**This corrects an earlier assumption in this project that Dart could not
determine an interface's netmask.** It can. A device can therefore compute its
own subnet's host range and its directed broadcast address without any user
input, which makes automatic subnet scanning feasible rather than something
the user must configure by hand.

Caveats: `broadcast` is nullable and IPv4-only; `prefixLength` is reported per
address, so a multi-homed host yields several candidate subnets. Link-local
(`169.254.0.0/16`) and loopback entries must be filtered out — the machine
used for development had four such addresses alongside its two real ones.

## TLS with mutual authentication — supported in pure Dart

`SecureServerSocket.bind` signature (dart:io):

```dart
static Future<SecureServerSocket> bind(
  dynamic address,
  int port,
  SecurityContext? context, {
  int backlog = 0,
  bool v6Only = false,
  bool requestClientCertificate = false,
  bool requireClientCertificate = false,
  List<String>? supportedProtocols,
  bool shared = false,
})
```

So a Dart TLS server **can require client certificates** without native code.

`SecurityContext` provides:

- `setTrustedCertificates(String file, {String? password})` /
  `setTrustedCertificatesBytes(...)`
- `useCertificateChain` / `useCertificateChainBytes`
- `usePrivateKey` / `usePrivateKeyBytes`
- `setClientAuthorities(String file, {String? password})` /
  `setClientAuthoritiesBytes(...)` — "the list of authority names that a
  `SecureServerSocket` will advertise as accepted when requesting a client
  certificate from a connecting client"
- `minimumTlsProtocolVersion` (settable)
- `setAlpnProtocols(List<String> protocols, bool isServer)`
- `allowLegacyUnsafeRenegotiation` — documented as "an extremely problematic
  protocol feature"; leave false.

Certificates and keys load from **PEM or PKCS12**.

`SecureSocket.connect(...)` accepts an `onBadCertificate` callback, which is
what permits pinning a self-signed certificate by fingerprint. `HttpClient`
exposes the equivalent `badCertificateCallback`.

**iOS caveat, from the Dart docs themselves:** "Some methods to add, remove,
and inspect certificates are not yet implemented" on iOS. The platform's
built-in trusted certificates remain available via
`SecurityContext.defaultContext`. This does not affect the v1 scope
(Windows + Android) but matters if iOS is added later.

## Consequences for the design

- Mutual TLS with self-signed certificates and fingerprint pinning is
  achievable with `dart:io` alone — no native plugin, no Rust core.
- Automatic subnet enumeration is possible, so "scan the subnet" can be
  offered without asking the user for a netmask.
- Dart's TLS is backed by BoringSSL in the runtime, so bulk encryption does
  not run as Dart bytecode.
