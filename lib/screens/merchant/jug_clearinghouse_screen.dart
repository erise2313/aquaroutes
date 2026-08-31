import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/jug_ledger.dart';
import '../../services/jug_ledger_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/error_state.dart';

/// Inter-Station Jug Clearinghouse: shows net balances of 5-gallon Slim/Round
/// jugs owed to/from other stations, and lets the owner propose a
/// settlement. Only the receiving (owed) station can confirm a settlement
/// (enforced by confirm_jug_settlement() RPC, not client logic) -- this
/// screen shows a "Confirm" action only on settlements where this station is
/// the owner_station_id of a proposed settlement.
class JugClearinghouseScreen extends StatefulWidget {
  const JugClearinghouseScreen({super.key});

  @override
  State<JugClearinghouseScreen> createState() => _JugClearinghouseScreenState();
}

class _JugClearinghouseScreenState extends State<JugClearinghouseScreen> {
  final _jugService = JugLedgerService(SupabaseService.instance);
  final _supabase = Supabase.instance.client;

  String? _stationId;
  Map<String, String> _stationNames = {};
  bool _isLoading = true;
  String? _error;
  List<JugBalance> _balances = [];
  List<JugSettlement> _settlements = [];

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
      final userId = _supabase.auth.currentUser!.id;
      final station = await _supabase.from('water_stations').select('id').eq('owner_profile_id', userId).maybeSingle();

      if (station == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final stationId = station['id'] as String;
      final balances = await _jugService.fetchBalancesForStation(stationId);
      final settlements = await _jugService.fetchSettlementsForStation(stationId);
      final allStations = await _supabase.from('water_stations').select('id, station_name');
      final names = {for (final s in allStations) s['id'] as String: s['station_name'] as String};

      if (mounted) {
        setState(() {
          _stationId = stationId;
          _balances = balances;
          _settlements = settlements;
          _stationNames = names;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load the jug clearinghouse: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showRecordTransferDialog() async {
    if (_stationId == null) return;
    final otherStations = await _jugService.fetchOtherStations(_stationId!);
    if (!mounted) return;
    if (otherStations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No other stations to record a transfer with.')));
      return;
    }

    String? selectedStationId = otherStations.first['id'] as String;
    JugType jugType = JugType.slim5gal;
    bool gaveJugs = true;
    final quantityController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Record a Jug Transfer'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedStationId,
                    decoration: const InputDecoration(labelText: 'Other Station'),
                    items: otherStations
                        .map((s) => DropdownMenuItem(value: s['id'] as String, child: Text(s['station_name'] as String)))
                        .toList(),
                    onChanged: (v) => setDialogState(() => selectedStationId = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<JugType>(
                    initialValue: jugType,
                    decoration: const InputDecoration(labelText: 'Jug Type'),
                    items: const [
                      DropdownMenuItem(value: JugType.slim5gal, child: Text('Slim 5-gal')),
                      DropdownMenuItem(value: JugType.round5gal, child: Text('Round 5-gal')),
                    ],
                    onChanged: (v) => setDialogState(() => jugType = v ?? jugType),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: quantityController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Quantity'),
                    validator: (v) {
                      final n = int.tryParse(v?.trim() ?? '');
                      return (n == null || n <= 0) ? 'Enter a valid quantity.' : null;
                    },
                  ),
                  const SizedBox(height: 12),
                  RadioGroup<bool>(
                    groupValue: gaveJugs,
                    onChanged: (v) => setDialogState(() => gaveJugs = v ?? gaveJugs),
                    child: const Column(
                      children: [
                        RadioListTile<bool>(value: true, title: Text('I gave them jugs'), contentPadding: EdgeInsets.zero),
                        RadioListTile<bool>(value: false, title: Text('I received jugs from them'), contentPadding: EdgeInsets.zero),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false) || selectedStationId == null) return;
                final quantity = int.parse(quantityController.text.trim());
                final holderStationId = gaveJugs ? selectedStationId! : _stationId!;
                final ownerStationId = gaveJugs ? _stationId! : selectedStationId!;
                Navigator.pop(dialogContext);
                try {
                  await _jugService.recordJugTransfer(
                    holderStationId: holderStationId,
                    ownerStationId: ownerStationId,
                    jugType: jugType,
                    quantity: quantity,
                    recordedByProfileId: _supabase.auth.currentUser!.id,
                  );
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Jug transfer recorded.')));
                  _load();
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              },
              child: const Text('Record'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _proposeSettlement(JugBalance balance) async {
    final isHolder = balance.holderStationId == _stationId;
    await _jugService.proposeSettlement(
      holderStationId: balance.holderStationId,
      ownerStationId: balance.ownerStationId,
      jugType: balance.jugType,
      quantity: balance.netQty.abs(),
      proposedByProfileId: _supabase.auth.currentUser!.id,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isHolder ? 'Settlement proposed to the owning station.' : 'Settlement proposed.')),
      );
    }
    _load();
  }

  Future<void> _confirmSettlement(JugSettlement settlement) async {
    try {
      await _jugService.confirmSettlement(settlement.id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settlement confirmed.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
    _load();
  }

  Future<void> _rejectSettlement(JugSettlement settlement) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Reject Settlement?',
      message: 'This proposed settlement will be marked rejected and cannot be confirmed later.',
      confirmLabel: 'Reject',
    );
    if (!confirmed) return;

    try {
      await _jugService.rejectSettlement(settlement.id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settlement rejected.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Jug Clearinghouse'),
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            tooltip: 'Record a Jug Transfer',
            onPressed: _stationId == null ? null : _showRecordTransferDialog,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? ErrorState(message: _error!, onRetry: _load)
          : _stationId == null
              ? const Center(child: Text('No station linked to this account.'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Text('Outstanding Balances', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      if (_balances.isEmpty) Text('No outstanding jug balances with other stations.', style: TextStyle(color: Colors.grey.shade700)),
                      ..._balances.map(_buildBalanceCard),
                      const SizedBox(height: 24),
                      const Text('Settlements', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      if (_settlements.isEmpty) Text('No settlement history yet.', style: TextStyle(color: Colors.grey.shade700)),
                      ..._settlements.map(_buildSettlementCard),
                    ],
                  ),
                ),
    );
  }

  Widget _buildBalanceCard(JugBalance balance) {
    final isHolder = balance.holderStationId == _stationId;
    final otherStationId = isHolder ? balance.ownerStationId : balance.holderStationId;
    final otherStationName = _stationNames[otherStationId] ?? 'Unknown Station';
    final jugLabel = balance.jugType == JugType.slim5gal ? 'Slim 5-gal' : 'Round 5-gal';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(Icons.water_drop, color: isHolder ? Colors.orange : Colors.blue),
        title: Text('$jugLabel · ${balance.netQty.abs()} jugs'),
        subtitle: Text(
          isHolder
              ? 'You are holding these jugs, owed to $otherStationName'
              : '$otherStationName is holding these jugs, owed to you',
        ),
        trailing: TextButton(
          onPressed: () => _proposeSettlement(balance),
          child: const Text('Propose Settlement'),
        ),
      ),
    );
  }

  Widget _buildSettlementCard(JugSettlement settlement) {
    final canConfirm = settlement.status == SettlementStatus.proposed && settlement.ownerStationId == _stationId;
    final holderName = _stationNames[settlement.holderStationId] ?? 'Unknown';
    final ownerName = _stationNames[settlement.ownerStationId] ?? 'Unknown';
    final jugLabel = settlement.jugType == JugType.slim5gal ? 'Slim 5-gal' : 'Round 5-gal';

    final (statusColor, statusLabel) = switch (settlement.status) {
      SettlementStatus.proposed => (Colors.orange, 'Proposed'),
      SettlementStatus.confirmed => (Colors.green, 'Confirmed'),
      SettlementStatus.rejected => (Colors.red, 'Rejected'),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text('$holderName → $ownerName: ${settlement.quantity} $jugLabel'),
        subtitle: Text(statusLabel, style: TextStyle(color: statusColor)),
        trailing: canConfirm
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton(
                    onPressed: () => _rejectSettlement(settlement),
                    child: const Text('Reject'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    onPressed: () => _confirmSettlement(settlement),
                    child: const Text('Confirm', style: TextStyle(color: Colors.white)),
                  ),
                ],
              )
            : null,
      ),
    );
  }
}
