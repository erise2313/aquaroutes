import 'package:flutter/material.dart';

/// Where "Back" goes inside a portal (owner, staff, officer) -- the pages
/// opened within a section, and the sections visited before this one.
///
/// Without it, a dashboard tile that switched to another section (or a
/// sidebar click) left no way back: the page header had no back button, the
/// phone's back button closed the app, and the browser's Back did nothing
/// or left the portal. Every forward step is recorded here, and every way of
/// going back -- the header's arrow, the phone's back button, the browser's
/// Back -- undoes the latest one.
class PortalBackController extends ChangeNotifier {
  final _entries = <_BackEntry>[];
  bool _undoingPush = false;

  /// Called after a step is recorded, so the website can add a browser
  /// history entry for it. [depth] is the number of steps now recorded.
  void Function(int depth)? onForward;

  bool get canGoBack => _entries.isNotEmpty;
  int get depth => _entries.length;

  /// A switch from section [previous] to another one.
  void recordSection(int previous, void Function(int) restore) {
    _entries.add(_BackEntry.section(() => restore(previous)));
    notifyListeners();
    onForward?.call(_entries.length);
  }

  /// A page pushed onto [navigator] within a section.
  void recordPush(NavigatorState navigator) {
    _entries.add(_BackEntry.push(navigator));
    notifyListeners();
    onForward?.call(_entries.length);
  }

  /// A page on [navigator] was closed some other way (saved, cancelled,
  /// "Done"); forget the step that opened it.
  void forgetPush(NavigatorState navigator) {
    if (_undoingPush) return;
    final i = _entries.lastIndexWhere((e) => e.navigator == navigator);
    if (i >= 0) {
      _entries.removeAt(i);
      notifyListeners();
    }
  }

  /// Undoes the latest step. False when there is nothing to go back to.
  bool back() {
    if (_entries.isEmpty) return false;
    final entry = _entries.removeLast();
    if (entry.navigator != null) {
      _undoingPush = true;
      try {
        entry.navigator!.pop();
      } finally {
        _undoingPush = false;
      }
    } else {
      entry.restore!();
    }
    notifyListeners();
    return true;
  }

  /// Back from an on-screen button: undoes the step and, on the website,
  /// takes the matching browser history entry back too, so the browser's
  /// own Back stays in step.
  void backFromButton() {
    if (back()) syncBrowserBack();
  }

  /// Undo steps until only [depth] remain -- the browser went back to an
  /// earlier entry.
  void trimTo(int depth) {
    while (_entries.length > depth && back()) {}
  }

  void Function() syncBrowserBack = () {};
}

class _BackEntry {
  _BackEntry.section(this.restore) : navigator = null;
  _BackEntry.push(this.navigator) : restore = null;

  final VoidCallback? restore;
  final NavigatorState? navigator;
}

/// Records pages pushed inside a section navigator.
class PortalBackObserver extends NavigatorObserver {
  PortalBackObserver(this.controller);

  final PortalBackController controller;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // Only real pages: the section's first page has no previous route, and
    // dialogs and sheets close themselves.
    if (previousRoute != null && route is PageRoute && navigator != null) controller.recordPush(navigator!);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute && navigator != null) controller.forgetPush(navigator!);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute && navigator != null) controller.forgetPush(navigator!);
  }
}

/// Makes the controller reachable from page headers.
class PortalBackScope extends InheritedNotifier<PortalBackController> {
  const PortalBackScope({super.key, required PortalBackController controller, required super.child})
      : super(notifier: controller);

  static PortalBackController? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PortalBackScope>()?.notifier;
}

/// Handles the phone's back button (and, in the admin portal, the browser's
/// Back) for a portal: undo the latest step, and only when there is none let
/// the app close.
class PortalBackHandler extends StatelessWidget {
  const PortalBackHandler({super.key, required this.controller, required this.child});

  final PortalBackController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => PopScope(
        canPop: !controller.canGoBack,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) controller.backFromButton();
        },
        child: child,
      ),
    );
  }
}
