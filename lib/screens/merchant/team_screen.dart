import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/brand_tokens.dart';
import '../../utils/error_text.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/error_state.dart';
import '../../widgets/portal/portal.dart';

/// The station's counter and dispatch staff, and the code they join with.
///
/// Staff can take orders, assign drivers and follow deliveries; they can't
/// touch permits, prices, products, drivers or settlements (enforced in the
/// database, supabase/patch_roles_governance.sql). The staff code is
/// separate from the drivers' invite code and expires after the
/// association's invite period; the owner renews it here.
class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _staff = [];
  String? _code;
  DateTime? _codeExpires;
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
      final userId = _supabase.auth.currentUser!.id;
      final staff = await _supabase.rpc('owner_list_staff');
      final station = await _supabase
          .from('water_stations')
          .select('staff_invite_code, staff_invite_expires_at')
          .eq('owner_profile_id', userId)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _staff = List<Map<String, dynamic>>.from(staff as List);
        _code = station?['staff_invite_code'] as String?;
        _codeExpires = DateTime.tryParse(station?['staff_invite_expires_at'] as String? ?? '')?.toLocal();
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load your team. ${describeError(e)}';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _issueCode() async {
    if (_code != null) {
      final ok = await showConfirmDialog(
        context,
        title: 'Issue a new staff code?',
        message: 'The current staff code stops working straight away. Staff already on your team are not affected.',
        confirmLabel: 'Issue new code',
        isDestructive: false,
      );
      if (!ok) return;
    }
    setState(() => _busy = true);
    try {
      await _supabase.rpc('owner_regenerate_staff_code');
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not issue a code. ${describeError(e)}')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(Map<String, dynamic> member) async {
    final name = (member['full_name'] as String?)?.trim();
    final ok = await showConfirmDialog(
      context,
      title: 'Remove ${name == null || name.isEmpty ? 'this staff member' : name}?',
      message: 'They lose access to your station straight away. You can add them again later with a new staff code.',
      confirmLabel: 'Remove',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await _supabase.rpc('owner_remove_staff', params: {'p_profile': member['profile_id']});
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not remove. ${describeError(e)}')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const PortalPageHeader(
            eyebrow: 'Your station',
            title: 'Team',
            subtitle: 'Counter and dispatch staff who help run your orders',
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? ErrorState(message: _error!, onRetry: _load)
                    : RefreshIndicator(onRefresh: _load, child: _buildBody()),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final theme = Theme.of(context);
    final density = PortalDensity.of(context);
    final expired = _codeExpires != null && _codeExpires!.isBefore(DateTime.now());

    return ListView(
      padding: density.pagePadding,
      children: [
        PortalSection(
          title: 'Staff code',
          subtitle: 'A new staff member chooses "Station Staff" when they register and enters this code.',
          child: PortalCard(
            lift: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_code == null)
                  Text('No staff code yet.', style: theme.textTheme.bodyMedium)
                else
                  Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          _code!,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_outlined),
                        tooltip: 'Copy staff code',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _code!));
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Staff code copied.')));
                        },
                      ),
                    ],
                  ),
                if (_codeExpires != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    expired
                        ? 'Expired -- issue a new code before someone joins.'
                        : 'Valid until ${DateFormat('MMM d, yyyy').format(_codeExpires!)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: expired ? BrandStatus.dangerFor(theme.brightness) : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _issueCode,
                  icon: const Icon(Icons.autorenew),
                  label: Text(_code == null ? 'Create a staff code' : 'Issue a new staff code'),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: density.sectionGap),
        PortalSection(
          title: 'Staff (${_staff.length})',
          subtitle: 'They can take orders, assign drivers and follow deliveries -- not permits, prices or drivers.',
          child: _staff.isEmpty
              ? const PortalEmptyState(
                  icon: Icons.badge_outlined,
                  title: 'No staff yet',
                  message: 'Share the staff code above with the person who runs your counter or dispatch.',
                )
              : Column(
                  children: [
                    for (final m in _staff)
                      PortalCard(
                        lift: false,
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            const Icon(Icons.person_outline),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (m['full_name'] as String?)?.trim().isNotEmpty == true ? m['full_name'] as String : 'Unnamed',
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  Text(
                                    [
                                      if ((m['phone_number'] as String?)?.isNotEmpty == true) m['phone_number'] as String,
                                      'since ${DateFormat('MMM d, yyyy').format(DateTime.parse(m['joined_at'] as String).toLocal())}',
                                    ].join(' · '),
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: _busy ? null : () => _remove(m),
                              child: const Text('Remove'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
