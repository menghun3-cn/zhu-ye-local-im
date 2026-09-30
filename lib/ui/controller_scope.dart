import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app.dart';

/// Makes the controller available to everything below it, and rebuilds what
/// reads it whenever the controller reports a change.
///
/// One notification at the root per change, rather than a subscription per
/// widget: the controller's `changes` stream is deliberately coarse, the views
/// it hands out are small value objects, and a tree that rebuilds wholesale
/// cannot race itself the way a dozen independent subscriptions can.
///
/// A page reads the controller with [ControllerScope.of] in its own `build` and
/// holds no subscription of its own — reading it is what subscribes it, so
/// there is nothing for a page to remember to cancel.
///
/// The notification has to travel through
/// [_ControllerProvider.updateShouldNotify]. Rebuilding this widget alone would
/// reach nothing: the [child] instance handed in here never changes, and Flutter
/// skips a subtree whose widget instance is identical.
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

  /// Always `true`, and it has to be.
  ///
  /// This widget is rebuilt only when the controller has reported a change (see
  /// [_ControllerScopeState]), and the controller instance is the same one for
  /// the life of the scope — so comparing the two would answer "no" every time
  /// and leave every page that reads the controller frozen at its first build.
  /// Everything the controller hands out is read inside `build`, so "a change
  /// happened" is exactly the question dependents want answered.
  @override
  bool updateShouldNotify(_ControllerProvider oldWidget) => true;
}
