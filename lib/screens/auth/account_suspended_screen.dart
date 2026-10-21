import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/error_text.dart';
import 'login_screen.dart';

/// Shown when a signed-in account has a membership row that exists but
/// isn't 'active' (suspended or revoked by a WASA admin, see
/// user_management_screen.dart) -- distinct from NoMembershipScreen, which
/// is for accounts with no membership row at all. AuthGate tells the two
/// apart via rawMembershipStatusProvider (providers/app_state.dart) since
/// the normal currentMembershipProvider filters status = 'active' and can't
/// distinguish "suspended" from "never assigned."
///
/// The person can appeal from here (submit_account_appeal,
/// patch_clearinghouse_appeals.sql): one written appeal at a time, decided
/// by a full officer or super admin, with the decision and note shown here.
class AccountSuspendedScreen extends StatefulWidget {
  const AccountSuspendedScreen({super.key});

  @override
  State<AccountSuspendedScreen> createState() => _AccountSuspendedScreenState();
}

class _AccountSuspendedScreenState extends State<AccountSuspendedScreen> {
  final _client = Supabase.instance.client;
  final _text = TextEditingController();
  Map<String, dynamic>? _latest;
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final row = await _client
          .from('account_appeals')
          .select('status, appeal_text, decision_note, created_at')
          .eq('profile_id', _client.auth.currentUser!.id)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (mounted) setState(() => _latest = row);
    } catch (_) {
      // The form still works; it just can't show a past appeal.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    if (_text.text.trim().length < 10) {
      setState(() => _error = 'Explain in a sentence or two why the suspension should be lifted.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await _client.rpc('submit_account_appeal', params: {'p_text': _text.text.trim()});
      _text.clear();
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _signOut() async {
    await _client.auth.signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final status = _latest?['status'] as String?;
    final pending = status == 'pending';

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.block, size: 48, color: theme.colorScheme.error),
                const SizedBox(height: 16),
                Text(
                  'Your account access has been suspended by WASA admin.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'If you believe this is a mistake, you can appeal below. A WASA officer reads it and decides.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: muted),
                ),
                const SizedBox(height: 24),
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else if (pending)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Your appeal is with WASA', style: theme.textTheme.titleSmall),
                          const SizedBox(height: 6),
                          Text('"${_latest!['appeal_text']}"', style: const TextStyle(fontStyle: FontStyle.italic)),
                          const SizedBox(height: 6),
                          Text('You will be notified, and the decision will show here.', style: TextStyle(color: muted)),
                        ],
                      ),
                    ),
                  )
                else ...[
                  if (status == 'kept_suspended')
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Your last appeal was not accepted', style: theme.textTheme.titleSmall),
                            if ((_latest!['decision_note'] as String?)?.isNotEmpty ?? false) ...[
                              const SizedBox(height: 6),
                              Text("WASA's note: ${_latest!['decision_note']}"),
                            ],
                            const SizedBox(height: 6),
                            Text('You can appeal again if something has changed.', style: TextStyle(color: muted)),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _text,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 1000,
                    enabled: !_sending,
                    decoration: InputDecoration(
                      labelText: 'Your appeal',
                      hintText: 'Why should the suspension be lifted?',
                      errorText: _error,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _sending ? null : _send,
                    child: _sending
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Send appeal to WASA'),
                  ),
                ],
                const SizedBox(height: 16),
                OutlinedButton(onPressed: _signOut, child: const Text('Sign Out')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
