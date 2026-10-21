import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/admin_palette.dart';
import '../../constants/app_colors.dart';
import '../../utils/error_text.dart';
import '../../widgets/admin_page_header.dart';
import '../../widgets/admin_status_pill.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/error_state.dart';
import '../../models/officer_role.dart';
import '../../widgets/portal/portal.dart';

/// Super admins only: the association's officers and super admins.
///
/// Officer power flows one way (UI/Roles plan): only a super admin can make
/// someone an officer, change an officer's role or suspend one, and the
/// database enforces it (guard_membership_change,
/// supabase/patch_roles_governance.sql) -- plain officers never see this
/// page. An officer must have an account of their own: a station owner,
/// staff member or driver can't be promoted, so nobody reviews their own
/// station. Nobody can suspend or demote themselves, and the last super
/// admin can't be removed.
class AdminOfficersScreen extends StatefulWidget {
  const AdminOfficersScreen({super.key});

  @override
  State<AdminOfficersScreen> createState() => _AdminOfficersScreenState();
}

class _AdminOfficersScreenState extends State<AdminOfficersScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _officers = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final rows = await _supabase
          .from('memberships')
          .select('id, profile_id, role, status, officer_role, profiles(full_name, phone_number)')
          .inFilter('role', ['wasa_superadmin', 'wasa_admin'])
          .order('role', ascending: false);
      if (mounted) {
        setState(() {
          _officers = List<Map<String, dynamic>>.from(rows);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load officers. ${describeError(e)}';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Picks an officer role, explaining what each may change.
  Future<OfficerRole?> _pickRole({required String title, OfficerRole? current}) {
    var selected = current ?? OfficerRole.officer;
    return showDialog<OfficerRole>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: RadioGroup<OfficerRole>(
              groupValue: selected,
              onChanged: (v) => setDialogState(() => selected = v ?? selected),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final role in OfficerRole.values)
                    RadioListTile<OfficerRole>(
                      value: role,
                      contentPadding: EdgeInsets.zero,
                      title: Text(role.label),
                      subtitle: Text(role.description),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, selected), child: const Text('Choose')),
          ],
        ),
      ),
    );
  }

  /// A new hire: the account is made here, with a temporary password shown
  /// once. They must set their own password at first sign-in.
  Future<void> _createOfficer() async {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    var role = OfficerRole.officer;
    String? error;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create an officer account'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('For a new hire. You get a temporary password to give them; they set their own the first time they sign in.'),
                  const SizedBox(height: 12),
                  TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Full name')),
                  const SizedBox(height: 12),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email address'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await _pickRole(title: 'Officer role', current: role);
                      if (picked != null) setDialogState(() => role = picked);
                    },
                    icon: const Icon(Icons.badge_outlined),
                    label: Text('Role: ${role.label}'),
                  ),
                  const SizedBox(height: 4),
                  Text(role.description, style: Theme.of(context).textTheme.bodySmall),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (nameController.text.trim().length < 2 || !emailController.text.contains('@')) {
                  setDialogState(() => error = 'Enter their full name and email address.');
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Create account'),
            ),
          ],
        ),
      ),
    );
    if (submitted != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final response = await _supabase.functions.invoke('create-officer', body: {
        'email': emailController.text.trim(),
        'full_name': nameController.text.trim(),
        'officer_role': role.key,
      });
      final data = response.data as Map;
      if (!mounted) return;
      await _showTemporaryPassword(data['email'] as String, data['temporary_password'] as String, role);
      await _load();
    } on FunctionException catch (e) {
      final details = e.details;
      final message = details is Map && details['error'] is String
          ? details['error'] as String
          : 'Could not create the account (error ${e.status}).';
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Shown once: the password is not stored anywhere it can be read back.
  Future<void> _showTemporaryPassword(String email, String password, OfficerRole role) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Account created'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$email is now a ${role.label.toLowerCase()}.'),
            const SizedBox(height: 12),
            const Text('Temporary password:'),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    password,
                    style: Theme.of(dialogContext).textTheme.headlineSmall?.copyWith(letterSpacing: 1.5),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy password',
                  icon: const Icon(Icons.copy_outlined),
                  onPressed: () => Clipboard.setData(ClipboardData(text: password)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Give it to them in person or by private message. This is the only time it is shown. '
              'They sign in at the admin portal and must choose their own password straight away.',
            ),
          ],
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Done'))],
      ),
    );
  }

  /// Someone who already has an account (for example a customer account).
  Future<void> _addOfficer() async {
    final emailController = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Promote an existing account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('For someone who already has a customer account. Enter the email they signed up with.'),
            const SizedBox(height: 12),
            TextField(
              controller: emailController,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email address'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, emailController.text.trim()), child: const Text('Find account')),
        ],
      ),
    );
    if (email == null || email.isEmpty || !mounted) return;

    List<Map<String, dynamic>> found;
    try {
      found = List<Map<String, dynamic>>.from(await _supabase.rpc('superadmin_find_account', params: {'p_email': email}) as List);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
      return;
    }
    if (!mounted) return;
    if (found.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No account uses $email. Use "Create officer account" instead.')));
      return;
    }
    final account = found.first;
    final name = (account['full_name'] as String?)?.trim();
    final currentRole = account['role'] as String?;
    if (currentRole == 'wasa_admin' || currentRole == 'wasa_superadmin') {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${name ?? email} is already an officer.')));
      return;
    }
    final role = await _pickRole(title: 'Make ${name == null || name.isEmpty ? email : name} an officer');
    if (role == null) return;
    await _run(
      () async {
        await _supabase.rpc('superadmin_set_role', params: {
          'p_profile': account['profile_id'],
          'p_role': role == OfficerRole.superadmin ? 'wasa_superadmin' : 'wasa_admin',
        });
        if (role != OfficerRole.superadmin) {
          await _supabase.rpc('superadmin_set_officer_role', params: {'p_profile': account['profile_id'], 'p_officer_role': role.key});
        }
      },
      '${name ?? email} is now a ${role.label.toLowerCase()}.',
    );
  }

  Future<void> _changeOfficerRole(Map<String, dynamic> m) async {
    final name = (m['profiles']?['full_name'] as String?) ?? 'This officer';
    final current = OfficerRole.fromMembership(m['role'] as String?, m['officer_role'] as String?);
    final role = await _pickRole(title: 'Role for $name', current: current);
    if (role == null || role == current) return;
    await _run(
      () => _supabase.rpc('superadmin_set_officer_role', params: {'p_profile': m['profile_id'], 'p_officer_role': role.key}),
      '$name is now a ${role.label.toLowerCase()}.',
    );
  }

  Future<void> _setRole(Map<String, dynamic> m, String role) async {
    final name = (m['profiles']?['full_name'] as String?) ?? 'This officer';
    final (title, message, label) = switch (role) {
      'wasa_superadmin' => (
          'Make $name a super admin?',
          'Super admins can also add, suspend and demote officers, transfer stations and change association settings. '
              'Keep this to two people (the president and secretary).',
          'Make super admin',
        ),
      'wasa_admin' => ('Make $name an officer only?', 'They keep officer powers but can no longer manage officers or settings.', 'Change role'),
      _ => (
          'End $name\'s officer access?',
          'Their account becomes a customer account. Their past decisions stay in the audit log under their name.',
          'End access',
        ),
    };
    final ok = await showConfirmDialog(context, title: title, message: message, confirmLabel: label, isDestructive: role == 'public_consumer');
    if (!ok) return;
    await _run(
      () => _supabase.rpc('superadmin_set_role', params: {'p_profile': m['profile_id'], 'p_role': role}),
      'Role updated.',
    );
  }

  Future<void> _toggleSuspend(Map<String, dynamic> m) async {
    final active = m['status'] == 'active';
    final name = (m['profiles']?['full_name'] as String?) ?? 'This officer';
    final ok = await showConfirmDialog(
      context,
      title: active ? 'Suspend $name?' : 'Reactivate $name?',
      message: active
          ? 'They can\'t sign in to the admin portal until reactivated. Nothing they did is undone.'
          : 'They regain their officer access.',
      confirmLabel: active ? 'Suspend' : 'Reactivate',
      isDestructive: active,
    );
    if (!ok) return;
    await _run(
      () => _supabase.from('memberships').update({'status': active ? 'suspended' : 'active'}).eq('id', m['id'] as String),
      active ? '$name suspended.' : '$name reactivated.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AdminPageHeader(
          eyebrow: 'Association',
          title: 'Officers',
          subtitle: 'Who can act for WASA, and with what powers',
          actions: [
            FilledButton.icon(
              onPressed: _busy ? null : _createOfficer,
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('Create officer account'),
            ),
            OutlinedButton(
              onPressed: _busy ? null : _addOfficer,
              child: const Text('Promote an existing account'),
            ),
          ],
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? ErrorState(message: _error!, onRetry: _load)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [for (final m in _officers) _buildTile(m)],
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildTile(Map<String, dynamic> m) {
    final palette = AdminPalette.of(context);
    final isSuper = m['role'] == 'wasa_superadmin';
    final officerRole = OfficerRole.fromMembership(m['role'] as String?, m['officer_role'] as String?);
    final active = m['status'] == 'active';
    final isSelf = m['profile_id'] == _supabase.auth.currentUser?.id;
    final name = (m['profiles']?['full_name'] as String?) ?? 'Unnamed';
    final phone = m['profiles']?['phone_number'] as String?;

    return PortalCard(
      lift: false,
      margin: const EdgeInsets.only(bottom: 10),
      accent: isSuper ? AppColors.seal : AppColors.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(name, style: TextStyle(fontWeight: FontWeight.w700, color: palette.ink)),
              AdminStatusPill(
                label: (officerRole?.label ?? 'Officer').toUpperCase(),
                color: isSuper ? AppColors.seal : AppColors.primary,
                icon: isSuper ? Icons.workspace_premium_outlined : Icons.verified_user_outlined,
              ),
              if (!active) const AdminStatusPill(label: 'SUSPENDED', color: AppColors.flagged),
              if (isSelf) Text('(you)', style: TextStyle(color: palette.inkMuted)),
            ],
          ),
          if (phone != null && phone.isNotEmpty) Text(phone, style: TextStyle(color: palette.inkMuted)),
          if (!isSelf) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _busy ? null : () => _changeOfficerRole(m),
                  child: const Text('Change role'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _toggleSuspend(m),
                  child: Text(active ? 'Suspend' : 'Reactivate'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _setRole(m, 'public_consumer'),
                  child: const Text('End officer access'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
