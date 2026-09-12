import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/app_colors.dart';
import '../../models/jug_ledger.dart';
import '../../services/jug_ledger_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/error_state.dart';
import '../../widgets/portal/portal.dart';
import '../../utils/error_text.dart';

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
  List<JugLedgerEntry> _ledgerEntries = [];

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
      final station = await _supabase.from('water_stations').select('id').eq('owner_profile_id', userId).maybeSingle();

      if (station == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final stationId = station['id'] as String;
      final balances = await _jugService.fetchBalancesForStation(stationId);
      final settlements = await _jugService.fetchSettlementsForStation(stationId);
      final ledgerEntries = await _jugService.fetchLedgerEntriesForStation(stationId);
      final allStations = await _supabase.from('water_stations').select('id, station_name');
      final names = {for (final s in allStations) s['id'] as String: s['station_name'] as String};

      if (mounted) {
        setState(() {
          _stationId = stationId;
          _balances = balances;
          _settlements = settlements;
          _ledgerEntries = ledgerEntries;
          _stationNames = names;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load the jug clearinghouse. ${describeError(e)}';
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
          title: const Text('Manual Adjustment'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Deliveries now record jug exchanges automatically. Only use this for corrections -- '
                    'a physical hand-off between stations directly, or fixing a mistake.',
                    style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                          color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
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
                final otherStationName = otherStations.firstWhere((s) => s['id'] == selectedStationId)['station_name'] as String;
                final jugLabel = jugType == JugType.slim5gal ? 'Slim 5-gal' : 'Round 5-gal';
                final holderName = gaveJugs ? otherStationName : 'You';
                Navigator.pop(dialogContext);

                // Recording is a raw, immediate ledger entry with no
                // undo/reject path (unlike settlements) -- confirm the
                // exact effect before writing it, since the wrong direction
                // silently pollutes both stations' balances.
                final confirmed = await showConfirmDialog(
                  context,
                  title: 'Confirm Jug Transfer',
                  message: '$holderName will now be recorded as holding $quantity $jugLabel belonging to '
                      '${gaveJugs ? 'you' : otherStationName}. This cannot be undone -- only a station settlement can later balance it out.',
                  confirmLabel: 'Record Transfer',
                );
                if (!confirmed) return;

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
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
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
    try {
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
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not propose settlement. ${describeError(e)}')));
    }
  }

  Future<void> _confirmSettlement(JugSettlement settlement) async {
    try {
      await _jugService.confirmSettlement(settlement.id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settlement confirmed.')));
    } on PostgrestException catch (e) {
      // e.message is already the clean sentence confirm_jug_settlement()
      // raises (e.g. the overdraft-guard message) -- showing the raw
      // exception instead would wrap it in "PostgrestException(message: ...,
      // code: ..., ...)".
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final density = PortalDensity.of(context);

    return Scaffold(
      body: Column(
        children: [
          PortalPageHeader(
            eyebrow: 'Governance & compliance',
            title: 'Jug Clearinghouse',
            subtitle: 'Whose 5-gallon jugs you are holding, and whose are holding yours',
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_note),
                tooltip: 'Manual adjustment (corrections only -- deliveries record themselves)',
                onPressed: _stationId == null ? null : _showRecordTransferDialog,
              ),
            ],
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? ErrorState(message: _error!, onRetry: _load)
                : _stationId == null
                ? const PortalEmptyState(
                    icon: Icons.storefront_outlined,
                    title: 'No station linked to this account',
                    message: 'Your account is not linked to a water station, so it has no jug balances.',
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: density.pagePadding,
                      children: [
                        PortalSection(
                          title: 'Outstanding balances',
                          subtitle: 'Net jugs between your station and each other station',
                          child: _balances.isEmpty
                              ? const PortalEmptyState(
                                  icon: Icons.check_circle_outline,
                                  title: 'Nothing outstanding',
                                  message: 'You have no unsettled jug balances with other stations.',
                                )
                              : Column(children: _balances.map(_buildBalanceCard).toList()),
                        ),
                        SizedBox(height: density.sectionGap),
                        PortalSection(
                          title: 'Settlements',
                          subtitle: 'Proposals to clear a balance, and what came of them',
                          child: _settlements.isEmpty
                              ? const PortalEmptyState(
                                  icon: Icons.handshake_outlined,
                                  title: 'No settlements yet',
                                  message: 'When you or another station proposes to settle a balance, it appears here.',
                                )
                              : Column(children: _settlements.map(_buildSettlementCard).toList()),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceCard(JugBalance balance) {
    final isHolder = balance.holderStationId == _stationId;
    final otherStationId = isHolder ? balance.ownerStationId : balance.holderStationId;
    final otherStationName = _stationNames[otherStationId] ?? 'Unknown Station';
    final jugLabel = balance.jugType == JugType.slim5gal ? 'Slim 5-gal' : 'Round 5-gal';

    // The individual events behind this net number -- "where are my jugs,"
    // concretely, instead of just a net count.
    final entries = _ledgerEntries
        .where((e) =>
            e.jugType == balance.jugType &&
            ((e.holderStationId == balance.holderStationId && e.ownerStationId == balance.ownerStationId) ||
                (e.holderStationId == balance.ownerStationId && e.ownerStationId == balance.holderStationId)))
        .toList();

    final theme = Theme.of(context);
    // Amber when the jugs are ours to return, the brand blue when they are
    // owed to us -- was a raw Colors.orange / Colors.blue.
    final tone = isHolder ? AppColors.pendingClearance : AppColors.primary;

    return PortalCard(
      lift: false,
      accent: tone,
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        // Deliberately NOT using ExpansionTile's `trailing` slot for the
        // settlement button -- that would silently replace the expand
        // chevron, leaving no visible sign the card can be opened to see
        // its entry history. The button goes under the subtitle instead,
        // which also keeps it off the title row where it could not shrink.
        leading: Icon(Icons.water_drop, color: StatusTint.onTint(context, tone)),
        title: Text('$jugLabel · ${balance.netQty.abs()} jugs', style: theme.textTheme.titleMedium),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isHolder
                  ? 'You are holding these jugs, owed to $otherStationName'
                  : '$otherStationName is holding these jugs, owed to you',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => _proposeSettlement(balance),
                child: const Text('Propose settlement'),
              ),
            ),
          ],
        ),
        children: entries.isEmpty
            ? [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    'No entry history found.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ]
            : entries.map((e) => _buildLedgerEntryRow(e, isHolder: e.holderStationId == _stationId)).toList(),
      ),
    );
  }

  Widget _buildLedgerEntryRow(JugLedgerEntry entry, {required bool isHolder}) {
    final date = DateFormat('MMM d, yyyy').format(entry.createdAt);
    final source = entry.relatedOrderId != null
        ? 'Delivery · order #${entry.relatedOrderId!.substring(0, 6).toUpperCase()}'
        : 'Manual adjustment';
    final direction = entry.quantity > 0 ? (isHolder ? 'received' : 'sent') : 'settled';
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text('$source · $date', style: theme.textTheme.bodySmall)),
          const SizedBox(width: 8),
          Text(
            '${entry.quantity > 0 ? '+' : ''}${entry.quantity} ($direction)',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettlementCard(JugSettlement settlement) {
    final canConfirm = settlement.status == SettlementStatus.proposed && settlement.ownerStationId == _stationId;
    final holderName = _stationNames[settlement.holderStationId] ?? 'Unknown';
    final ownerName = _stationNames[settlement.ownerStationId] ?? 'Unknown';
    final jugLabel = settlement.jugType == JugType.slim5gal ? 'Slim 5-gal' : 'Round 5-gal';

    final theme = Theme.of(context);

    final (statusColor, statusLabel) = switch (settlement.status) {
      SettlementStatus.proposed => (AppColors.pendingClearance, 'PROPOSED'),
      SettlementStatus.confirmed => (AppColors.cleared, 'CONFIRMED'),
      SettlementStatus.rejected => (AppColors.flagged, 'REJECTED'),
    };

    return PortalCard(
      lift: false,
      accent: statusColor,
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$holderName → $ownerName', style: theme.textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(
            '${settlement.quantity} $jugLabel',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          StatusPill(label: statusLabel, color: statusColor),
          // Only the owed station can confirm -- enforced by
          // confirm_jug_settlement(), not by hiding the button.
          if (canConfirm) ...[
            const SizedBox(height: 12),
            PortalActionRow(
              children: [
                OutlinedButton(
                  onPressed: () => _rejectSettlement(settlement),
                  child: const Text('Reject'),
                ),
                FilledButton(
                  onPressed: () => _confirmSettlement(settlement),
                  child: const Text('Confirm'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
