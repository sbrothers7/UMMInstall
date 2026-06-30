import 'package:flutter/widgets.dart';
import '../app_state.dart';

/// Provides [AppState] to the widget tree and rebuilds dependents when it
/// notifies — a dependency-free stand-in for a state-management package.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found in context');
    return scope!.notifier!;
  }
}
