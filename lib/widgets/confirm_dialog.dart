import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// Reusable destructive/non-destructive confirmation prompt. Several admin
/// and owner actions (rejecting a permit, confirming a flag, removing a
/// worker, deleting a bulletin) previously fired immediately on tap with no
/// "are you sure?" step -- this centralizes that one missing step instead
/// of repeating the same AlertDialog boilerplate at each call site.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool isDestructive = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: isDestructive ? AppColors.flagged : AppColors.primary,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel, style: const TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
  return result ?? false;
}
