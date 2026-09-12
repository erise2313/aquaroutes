import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/app_state.dart';
import '../providers/app_theme_provider.dart';
import '../services/account_service.dart';
import '../services/supabase_service.dart';
import 'change_password_dialog.dart';
import '../utils/error_text.dart';

/// "Account" block shared by every signed-in surface: change password, and
/// either delete the account (customers) or request its deletion (station
/// owners, drivers, admins -- see [deletionModeFor]).
///
/// [textColor]/[mutedColor] let the driver portal's dark palette use it;
/// elsewhere the surrounding theme decides.
class AccountSettingsSection extends ConsumerStatefulWidget {
  const AccountSettingsSection({super.key, this.textColor, this.mutedColor});

  final Color? textColor;
  final Color? mutedColor;

  @override
  ConsumerState<AccountSettingsSection> createState() => _AccountSettingsSectionState();
}

class _AccountSettingsSectionState extends ConsumerState<AccountSettingsSection> {
  final _service = AccountService(SupabaseService.instance);
  AccountDeletionRequest? _pending;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadPending();
  }

  Future<void> _loadPending() async {
    try {
      final pending = await _service.fetchMyPendingRequest();
      if (mounted) setState(() => _pending = pending);
    } catch (_) {
      // Only decides which button shows; the request button still works.
    }
  }

  void _snack(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _changePassword() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => ChangePasswordDialog(
        onSubmit: (current, next) => _service.changePassword(current: current, next: next),
      ),
    );
    if (changed == true) _snack('Password changed.');
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(context: context, builder: (_) => const _DeleteAccountDialog());
    if (confirmed != true || !mounted) return;

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await _service.deleteMyAccount();
      navigator.popUntil((route) => route.isFirst);
      messenger.showSnackBar(const SnackBar(content: Text('Your account has been deleted.')));
      // The login no longer exists; this clears the local session so the app
      // returns to its signed-out state.
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (_) {}
    } on AccountException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Could not delete your account. ${describeError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestDeletion() async {
    final reason = await showDialog<String>(context: context, builder: (_) => const _DeletionRequestDialog());
    if (reason == null) return;
    setState(() => _busy = true);
    try {
      await _service.requestDeletion(reason);
      await _loadPending();
      _snack('Request sent. WASA admin will review it.');
    } catch (e) {
      _snack('Could not send the request. ${describeError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelRequest() async {
    final pending = _pending;
    if (pending == null) return;
    setState(() => _busy = true);
    try {
      await _service.cancelDeletionRequest(pending.id);
      if (mounted) setState(() => _pending = null);
      _snack('Deletion request withdrawn.');
    } catch (e) {
      _snack('Could not withdraw the request. ${describeError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(currentMembershipProvider).value?.role;
    final mode = deletionModeFor(role);
    final theme = Theme.of(context);
    final text = widget.textColor ?? theme.colorScheme.onSurface;
    final muted = widget.mutedColor ?? theme.colorScheme.onSurfaceVariant;
    final danger = theme.colorScheme.error;
    final pending = _pending;

    final heading = TextStyle(color: muted, letterSpacing: 1.2, fontSize: 12, fontWeight: FontWeight.w600);
    final themeMode = ref.watch(appThemeProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('APPEARANCE', style: heading),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          // Chips rather than a SegmentedButton: three labels in one row
          // overflow once the system font size is turned up.
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in AppThemeMode.values)
                ChoiceChip(
                  label: Text(option.label),
                  selected: themeMode == option,
                  onSelected: (_) => ref.read(appThemeProvider.notifier).set(option),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('ACCOUNT', style: heading),
        ),
        ListTile(
          enabled: !_busy,
          leading: Icon(Icons.lock_reset, color: text),
          title: Text('Change password', style: TextStyle(color: text)),
          onTap: _changePassword,
        ),
        if (mode == DeletionMode.selfService)
          ListTile(
            enabled: !_busy,
            leading: Icon(Icons.delete_forever_outlined, color: danger),
            title: Text('Delete account', style: TextStyle(color: danger)),
            subtitle: Text('Permanently remove your account and personal details', style: TextStyle(color: muted)),
            onTap: _deleteAccount,
          )
        else if (pending != null)
          ListTile(
            enabled: !_busy,
            leading: Icon(Icons.hourglass_top, color: text),
            title: Text('Deletion requested', style: TextStyle(color: text)),
            subtitle: Text(
              'Sent ${DateFormat('MMM d, yyyy').format(pending.requestedAt)}. WASA admin will contact you.',
              style: TextStyle(color: muted),
            ),
            trailing: TextButton(onPressed: _busy ? null : _cancelRequest, child: const Text('Withdraw')),
          )
        else
          ListTile(
            enabled: !_busy,
            leading: Icon(Icons.person_remove_outlined, color: danger),
            title: Text('Request account deletion', style: TextStyle(color: danger)),
            subtitle: Text('WASA admin reviews station, driver and admin accounts', style: TextStyle(color: muted)),
            onTap: _requestDeletion,
          ),
      ],
    );
  }
}

/// Spells out what deletion removes and keeps, and asks for "DELETE" typed
/// out, since it can't be undone.
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final confirmed = _controller.text.trim().toUpperCase() == 'DELETE';
    return AlertDialog(
      title: const Text('Delete your account?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This removes your login, name, phone number, photo, reviews and comments. It cannot be undone.\n\n'
              "Stations keep a record of your past orders' items and amounts, without your name, phone "
              'or exact address.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Type DELETE to confirm'),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
          onPressed: confirmed ? () => Navigator.pop(context, true) : null,
          child: const Text('Delete account'),
        ),
      ],
    );
  }
}

/// Pops with the (possibly empty) reason, or null when cancelled.
class _DeletionRequestDialog extends StatefulWidget {
  const _DeletionRequestDialog();

  @override
  State<_DeletionRequestDialog> createState() => _DeletionRequestDialogState();
}

class _DeletionRequestDialogState extends State<_DeletionRequestDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Request account deletion'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your account is linked to association records, so WASA admin completes the deletion '
              '(for example, closing your station first). You can withdraw the request until then.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              maxLines: 3,
              maxLength: 1000,
              decoration: const InputDecoration(labelText: 'Reason (optional)', border: OutlineInputBorder()),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _controller.text), child: const Text('Send request')),
      ],
    );
  }
}
