import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/membership.dart';
import 'help_content.dart';

String _seenKey(AppRole role) => 'tour_seen_${role.name}';

/// Shows the role's three-page tour. Without [force], only the first time
/// this role signs in on this device.
Future<void> showFirstRunTour(BuildContext context, AppRole role, {bool force = false}) async {
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
    if (!force && (prefs.getBool(_seenKey(role)) ?? false)) return;
  } catch (_) {
    if (!force) return;
  }
  if (!context.mounted) return;
  await showDialog<void>(context: context, builder: (_) => _TourDialog(pages: tourPagesFor(role)));
  try {
    await prefs?.setBool(_seenKey(role), true);
  } catch (_) {}
}

/// Wraps a role's home and shows its tour once, after the first frame.
class FirstRunTourGate extends StatefulWidget {
  const FirstRunTourGate({super.key, required this.role, required this.child});

  final AppRole role;
  final Widget child;

  @override
  State<FirstRunTourGate> createState() => _FirstRunTourGateState();
}

class _FirstRunTourGateState extends State<FirstRunTourGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showFirstRunTour(context, widget.role);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _TourDialog extends StatefulWidget {
  const _TourDialog({required this.pages});

  final List<TourPage> pages;

  @override
  State<_TourDialog> createState() => _TourDialogState();
}

class _TourDialogState extends State<_TourDialog> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final page = widget.pages[_index];
    final last = _index == widget.pages.length - 1;
    return AlertDialog(
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(page.icon, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(page.title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            Text(page.body, style: theme.textTheme.bodyLarge, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Text('${_index + 1} of ${widget.pages.length}', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(last ? 'Close' : 'Skip')),
        if (_index > 0) OutlinedButton(onPressed: () => setState(() => _index--), child: const Text('Back')),
        FilledButton(
          onPressed: last ? () => Navigator.pop(context) : () => setState(() => _index++),
          child: Text(last ? 'Get started' : 'Next'),
        ),
      ],
    );
  }
}
