import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/error_text.dart';
import '../../widgets/admin_page_header.dart';
import '../../widgets/error_state.dart';
import '../../widgets/portal/portal.dart';

/// Super admins only: rules the board sets once, in its resolution, and
/// the system then applies the same way to every station.
///
///  * Grace period -- days a station keeps its accreditation after a
///    required permit expires before it is marked Lapsed.
///  * Invite validity -- days a driver or staff invite code works after the
///    owner issues it.
///
/// Stored in association_settings (supabase/patch_roles_governance.sql),
/// which only a super admin can change.
class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  String? _error;
  int _graceDays = 30;
  int _inviteDays = 7;
  int _savedGrace = 30;
  int _savedInvite = 7;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final row = await _supabase.from('association_settings').select('grace_days, invite_valid_days').maybeSingle();
      if (!mounted) return;
      setState(() {
        _graceDays = _savedGrace = (row?['grace_days'] as num?)?.toInt() ?? 30;
        _inviteDays = _savedInvite = (row?['invite_valid_days'] as num?)?.toInt() ?? 7;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load settings. ${describeError(e)}';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _supabase.from('association_settings').update({
        'grace_days': _graceDays,
        'invite_valid_days': _inviteDays,
        'updated_by': _supabase.auth.currentUser?.id,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', true);
      if (!mounted) return;
      setState(() {
        _savedGrace = _graceDays;
        _savedInvite = _inviteDays;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save. ${describeError(e)}')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final changed = _graceDays != _savedGrace || _inviteDays != _savedInvite;
    return Column(
      children: [
        const AdminPageHeader(
          eyebrow: 'Association',
          title: 'Settings',
          subtitle: 'Rules the board sets once and the system applies to every station',
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? ErrorState(message: _error!, onRetry: _load)
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _Stepper(
                          title: 'Grace period',
                          help: 'Days a station keeps its accreditation after a required permit expires, before it is '
                              'marked Lapsed. Reminders go out 30 and 7 days before expiry either way.',
                          value: _graceDays,
                          min: 0,
                          max: 365,
                          step: 5,
                          unit: 'days',
                          onChanged: (v) => setState(() => _graceDays = v),
                        ),
                        const SizedBox(height: 12),
                        _Stepper(
                          title: 'Invite codes stay valid for',
                          help: 'After an owner issues a driver or staff code, it works for this many days. Codes '
                              'issued before this setting existed keep working until renewed.',
                          value: _inviteDays,
                          min: 1,
                          max: 90,
                          step: 1,
                          unit: 'days',
                          onChanged: (v) => setState(() => _inviteDays = v),
                        ),
                        const SizedBox(height: 20),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.icon(
                            onPressed: changed && !_saving ? _save : null,
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('Save settings'),
                          ),
                        ),
                      ],
                    ),
        ),
      ],
    );
  }
}

/// A number with − and + buttons rather than a text field: easier to hit,
/// and it can't hold something that isn't a number.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.title,
    required this.help,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.unit,
    required this.onChanged,
  });

  final String title;
  final String help;
  final int value;
  final int min;
  final int max;
  final int step;
  final String unit;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PortalCard(
      lift: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(help, style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton.outlined(
                tooltip: 'Fewer $unit',
                onPressed: value > min ? () => onChanged((value - step).clamp(min, max)) : null,
                icon: const Icon(Icons.remove),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('$value $unit', style: theme.textTheme.titleLarge),
              ),
              IconButton.outlined(
                tooltip: 'More $unit',
                onPressed: value < max ? () => onChanged((value + step).clamp(min, max)) : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
