import 'package:flutter/widgets.dart';

/// Disposes [notifiers] when this widget leaves the tree.
///
/// For dialogs that create their controllers in the method that shows them:
/// wrap the dialog in this instead of disposing when `showDialog`'s future
/// completes. That future completes as soon as the dialog is popped, while
/// it is still on screen animating out, and its text fields still use the
/// controllers until the exit animation ends -- disposing then throws "used
/// after being disposed".
class DisposeWith extends StatefulWidget {
  const DisposeWith({super.key, required this.notifiers, required this.child});

  final List<ChangeNotifier> notifiers;
  final Widget child;

  @override
  State<DisposeWith> createState() => _DisposeWithState();
}

class _DisposeWithState extends State<DisposeWith> {
  @override
  void dispose() {
    for (final notifier in widget.notifiers) {
      notifier.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
