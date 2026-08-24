import 'package:flutter/material.dart';

/// Shared "fetch failed" state -- several screens previously had no
/// try/catch around their initial data fetch, so a throw (network blip,
/// RLS denial, etc.) left `_isLoading` stuck `true` forever with an
/// indefinite spinner and no way to retry. Pair with a try/catch that sets
/// an error message on failure instead of leaving loading stuck.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.grey.shade500),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
