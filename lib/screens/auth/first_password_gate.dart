import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/error_text.dart';
import '../../widgets/wasa_shield_logo.dart';

/// Before an officer created by a super admin can use the portal, they
/// replace the temporary password they were given (create-officer edge
/// function sets profiles.must_change_password).
class FirstPasswordGate extends StatefulWidget {
  const FirstPasswordGate({super.key, required this.child});

  final Widget child;

  @override
  State<FirstPasswordGate> createState() => _FirstPasswordGateState();
}

class _FirstPasswordGateState extends State<FirstPasswordGate> {
  final _client = Supabase.instance.client;
  bool? _mustChange;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final row = await _client
          .from('profiles')
          .select('must_change_password')
          .eq('id', _client.auth.currentUser!.id)
          .maybeSingle();
      if (mounted) setState(() => _mustChange = row?['must_change_password'] == true);
    } catch (_) {
      // Can't tell: let them in rather than lock them out of the portal.
      if (mounted) setState(() => _mustChange = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (_mustChange) {
      null => const Scaffold(body: Center(child: CircularProgressIndicator())),
      true => _ChooseYourPassword(onDone: () => setState(() => _mustChange = false)),
      false => widget.child,
    };
  }
}

class _ChooseYourPassword extends StatefulWidget {
  const _ChooseYourPassword({required this.onDone});

  final VoidCallback onDone;

  @override
  State<_ChooseYourPassword> createState() => _ChooseYourPasswordState();
}

class _ChooseYourPasswordState extends State<_ChooseYourPassword> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final client = Supabase.instance.client;
    try {
      await client.auth.updateUser(UserAttributes(password: _password.text));
      await client.rpc('clear_must_change_password');
      widget.onDone();
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = describeError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: WasaShieldLogo(size: 56)),
                  const SizedBox(height: 20),
                  Text('Choose your password', textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    'You signed in with a temporary password. Choose one only you know before continuing.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'New password', helperText: 'At least 8 characters'),
                    validator: (v) => (v ?? '').length < 8 ? 'At least 8 characters' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirm,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Type it again'),
                    validator: (v) => v != _password.text ? 'The two passwords differ' : null,
                    onFieldSubmitted: (_) => _save(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Save and continue'),
                  ),
                  TextButton(
                    onPressed: _saving ? null : () => Supabase.instance.client.auth.signOut(),
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
