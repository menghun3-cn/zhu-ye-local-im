import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app.dart';

/// Makes the controller available to everything below it, and rebuilds that
/// subtree whenever the controller reports a change.
///
/// One rebuild at the root per change, rather than a subscription per widget:
/// the controller's `changes` stream is deliberately coarse, the views it
/// hands out are small value objects, and a tree that rebuilds wholesale cannot
/// race itself the way a dozen independent subscriptions can.
///
/// A page reads the controller with [ControllerScope.of] in its own `build` and
/// holds no subscription of its own — with the whole subtree rebuilt on every
/// change there is nothing for a page to subscribe to, and nothing for it to
/// forget to cancel.
class ControllerScope extends StatefulWidget {
  /// Exposes [controller] to [child].
  const ControllerScope({
    super.key,
    required this.controller,
    required this.child,
  });

  /// The one object a screen talks to.
  final LocalTransferController controller;

  /// The subtree that may read it.
  final Widget child;

  /// The controller above [context].
  ///
  /// Throws [StateError] rather than returning null: every page in this app is
  /// built inside a scope, and a page that is not is a wiring mistake worth
  /// failing loudly on.
  static LocalTransferController of(BuildContext context) {
    final provider = context
        .dependOnInheritedWidgetOfExactType<_ControllerProvider>();
    if (provider == null) {
      throw StateError('no ControllerScope above this widget');
    }
    return provider.controller;
  }

  @override
  State<ControllerScope> createState() => _ControllerScopeState();
}

class _ControllerScopeState extends State<ControllerScope> {
  late final StreamSubscription<void> _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.controller.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _ControllerProvider(controller: widget.controller, child: widget.child);
}

final class _ControllerProvider extends InheritedWidget {
  const _ControllerProvider({required this.controller, required super.child});

  final LocalTransferController controller;

  @override
  bool updateShouldNotify(_ControllerProvider oldWidget) =>
      !identical(oldWidget.controller, controller);
}
