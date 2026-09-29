# Local Transfer

A peer-to-peer tool for moving text, files, and clipboard content between
devices on a local network. No server, no account, no cloud.

- v1 platforms: Windows and Android.
- Product vocabulary: [CONTEXT.md](CONTEXT.md)
- Repository conventions — branching, commits, gates: [AGENTS.md](AGENTS.md)
- Architecture and platform decisions: [.agents/notes/](.agents/notes/)
- Platform facts verified on real hardware: [docs/](docs/)

## Development

Requires the current Flutter stable (3.47.x / Dart 3.13.x).

```sh
flutter pub get
flutter analyze
dart format --set-exit-if-changed .
flutter test
```

The Windows and Android build pipelines are additional gates:

```sh
flutter build windows --debug
flutter build apk --debug
```
