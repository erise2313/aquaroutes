import 'package:flutter/material.dart';

import '../services/account_service.dart';
import '../utils/error_text.dart';

/// Asks for the current password and a new one (twice). [onSubmit] does the
/// change; an [AccountException] it throws is shown in the dialog. Pops with
/// `true` once the password has changed.
///
/// Owns its controllers: a dialog is still on screen during its exit
/// animation, so disposing them when showDialog's future completes is too
/// early.
class ChangePasswordDialog extends StatefulWidget {
  const ChangePasswordDialog({super.key, required this.onSubmit});

  final Future<void> Function(String current, String next) onSubmit;

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _nextController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscured = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _currentController.dispose();
    _nextController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_currentController.text, _nextController.text);
      if (mounted) Navigator.pop(context, true);
    } on AccountException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not change your password. ${describeError(e)}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibility = IconButton(
      tooltip: _obscured ? 'Show passwords' : 'Hide passwords',
      icon: Icon(_obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined),
      onPressed: () => setState(() => _obscured = !_obscured),
    );
    return AlertDialog(
      title: const Text('Change password'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _currentController,
                obscureText: _obscured,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(labelText: 'Current password', suffixIcon: visibility),
                validator: (v) => (v ?? '').isEmpty ? 'Enter your current password' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nextController,
                obscureText: _obscured,
                autofillHints: const [AutofillHints.newPassword],
                decoration: const InputDecoration(labelText: 'New password', helperText: 'At least 8 characters'),
                validator: validateNewPassword,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _confirmController,
                obscureText: _obscured,
                decoration: const InputDecoration(labelText: 'Confirm new password'),
                validator: (v) => v != _nextController.text ? "The passwords don't match" : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Change password'),
        ),
      ],
    );
  }
}
