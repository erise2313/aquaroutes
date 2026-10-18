import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/error_text.dart';
import '../../widgets/confirm_dialog.dart';

/// Super admins only: moves a station to a new owner (a sale or an
/// inheritance) without re-creating it -- orders, permits, jug balances,
/// staff and drivers all stay with the station. The new owner must be a
/// customer account with no other role; the previous owner becomes one.
/// See superadmin_transfer_station (supabase/patch_roles_governance.sql).
///
/// Renders nothing for anyone who isn't a super admin.
class TransferStationButton extends StatefulWidget {
  const TransferStationButton({super.key, required this.stationId, required this.stationName, this.onTransferred});

  final String stationId;
  final String stationName;
  final VoidCallback? onTransferred;

  @override
  State<TransferStationButton> createState() => _TransferStationButtonState();
}

class _TransferStationButtonState extends State<TransferStationButton> {
  final _supabase = Supabase.instance.client;
  bool _isSuperadmin = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final result = await _supabase.rpc('auth_is_superadmin');
      if (mounted) setState(() => _isSuperadmin = result == true);
    } catch (_) {
      // Not shown when it can't be confirmed.
    }
  }

  Future<void> _transfer() async {
    final controller = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Transfer ${widget.stationName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('The new owner registers in the app as a customer first. Enter the email they used.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'New owner\'s email'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Find account')),
        ],
      ),
    );
    if (email == null || email.isEmpty || !mounted) return;

    setState(() => _busy = true);
    try {
      final found = List<Map<String, dynamic>>.from(
        await _supabase.rpc('superadmin_find_account', params: {'p_email': email}) as List,
      );
      if (!mounted) return;
      if (found.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No account uses $email. Ask them to register first.')));
        return;
      }
      final account = found.first;
      final role = account['role'] as String?;
      if (role != null && role != 'public_consumer') {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('That account already has a role (officer, owner, staff or driver). The new owner needs a customer account.'),
        ));
        return;
      }
      final name = (account['full_name'] as String?)?.trim();
      final ok = await showConfirmDialog(
        context,
        title: 'Transfer ${widget.stationName} to ${name == null || name.isEmpty ? email : name}?',
        message: 'The station keeps its orders, permits, jug balances, staff and drivers. The current owner loses '
            'access and their account becomes a customer account. Both are notified.',
        confirmLabel: 'Transfer station',
      );
      if (!ok) return;
      await _supabase.rpc('superadmin_transfer_station', params: {
        'p_station_id': widget.stationId,
        'p_new_owner': account['profile_id'],
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${widget.stationName} transferred.')));
      widget.onTransferred?.call();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isSuperadmin) return const SizedBox.shrink();
    return OutlinedButton.icon(
      onPressed: _busy ? null : _transfer,
      icon: const Icon(Icons.swap_horizontal_circle_outlined),
      label: const Text('Transfer ownership'),
    );
  }
}
