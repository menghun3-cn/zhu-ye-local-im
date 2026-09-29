import 'package:flutter/material.dart';

void main() {
  runApp(const LocalTransferApp());
}

/// Root widget of the application.
///
/// The interface is deliberately empty for now. It exists so that the Windows
/// and Android build pipelines, the test harness, and the lint gate all have a
/// real entry point to run against; user-facing features land in later changes.
class LocalTransferApp extends StatelessWidget {
  const LocalTransferApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Local Transfer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const HomePage(),
    );
  }
}

/// Placeholder home screen.
///
/// Discovery, Transfers, and Clipboard Mirroring each get their own surface
/// here once they exist.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Local Transfer')),
      body: const Center(child: Text('No devices discovered yet.')),
    );
  }
}
