import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../constants/app_colors.dart';
import '../../models/worker.dart';
import '../../services/supabase_service.dart';
import '../../services/worker_service.dart';
import '../../utils/error_text.dart';
import '../../widgets/portal/portal.dart';

/// Search a prospective driver's clearance history across the whole
/// association before hiring them -- directly addresses the "driver
/// poaching / rehired elsewhere after theft" problem the Worker Security
/// Registry exists for. Deliberately shows only a summary (clearance
/// status, confirmed-incident count, station history) via the
/// hire_check_search()/hire_check_station_history() RPCs
/// (supabase/migrations/0005_workers.sql) -- never another station's
/// incident descriptions or amounts.
class HireCheckScreen extends StatefulWidget {
  const HireCheckScreen({super.key});

  @override
  State<HireCheckScreen> createState() => _HireCheckScreenState();
}

class _HireCheckScreenState extends State<HireCheckScreen> {
  final _workerService = WorkerService(SupabaseService.instance);
  final _searchController = TextEditingController();

  bool _isSearching = false;
  bool _hasSearched = false;
  List<HireCheckResult> _results = [];
  String? _loadingHistoryWorkerId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _hasSearched = true;
    });

    try {
      final results = await _workerService.hireCheckSearch(query);
      if (mounted) setState(() => _results = results);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
      }
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _showHistory(HireCheckResult result) async {
    setState(() => _loadingHistoryWorkerId = result.workerId);
    final List<WorkerStationHistoryEntry> history;
    try {
      history = await _workerService.fetchStationHistory(result.workerId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load station history. ${describeError(e)}')));
      }
      return;
    } finally {
      if (mounted) setState(() => _loadingHistoryWorkerId = null);
    }
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${result.fullName} -- station history', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (history.isEmpty)
              const PortalEmptyState(
                icon: Icons.store_outlined,
                title: 'No station history',
                message: 'This worker has not been on any station roster yet.',
              ),
            ...history.map((h) {
              final range = h.leftAt == null
                  ? '${DateFormat('MMM yyyy').format(h.joinedAt)} -- present'
                  : '${DateFormat('MMM yyyy').format(h.joinedAt)} -- ${DateFormat('MMM yyyy').format(h.leftAt!)}';
              final isActive = h.status == StationHistoryStatus.active;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  isActive ? Icons.store : Icons.store_outlined,
                  color: isActive
                      ? StatusTint.onTint(context, AppColors.cleared)
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                title: Text(h.stationName),
                subtitle: Text('$range${h.status == StationHistoryStatus.removed ? " (removed by station)" : ""}'),
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final density = PortalDensity.of(context);

    return Scaffold(
      body: Column(
        children: [
          const PortalPageHeader(
            eyebrow: 'Governance & compliance',
            title: 'Hire Check',
            subtitle: 'Check a worker\'s clearance across the association before you hire them',
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              density.pagePadding.left,
              density.pagePadding.top,
              density.pagePadding.right,
              0,
            ),
            child: _buildSearchRow(density),
          ),
          Expanded(child: _buildResults(density)),
        ],
      ),
    );
  }

  /// The field and its button stack on a narrow screen: side by side, the
  /// button is a non-flexible child whose label cannot shrink, which is what
  /// overflowed the order card at large system text.
  Widget _buildSearchRow(PortalDensity density) {
    final field = TextField(
      controller: _searchController,
      decoration: const InputDecoration(
        labelText: 'Name or worker code',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.search),
      ),
      onSubmitted: (_) => _search(),
    );

    final button = FilledButton(
      onPressed: _isSearching ? null : _search,
      child: _isSearching
          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Text('Search'),
    );

    if (!density.isWide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [field, const SizedBox(height: 10), button],
      );
    }

    return Row(
      children: [
        Expanded(child: field),
        const SizedBox(width: 8),
        button,
      ],
    );
  }

  Widget _buildResults(PortalDensity density) {
    if (!_hasSearched) {
      return const PortalEmptyState(
        icon: Icons.person_search_outlined,
        title: 'Search before you hire',
        message: 'Enter a name or worker code above. You will see their clearance status and how many '
            'incidents were confirmed against them -- never another station\'s incident details.',
      );
    }

    if (_results.isEmpty) {
      return const PortalEmptyState(
        icon: Icons.search_off,
        title: 'No matching workers',
        message: 'Nobody in the association register matches that name or worker code.',
      );
    }

    return ListView.builder(
      padding: density.pagePadding,
      itemCount: _results.length,
      itemBuilder: (context, index) =>
          _buildResultCard(_results[index], last: index == _results.length - 1, density: density),
    );
  }

  Widget _buildResultCard(HireCheckResult result, {required bool last, required PortalDensity density}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final (color, label) = switch (result.clearanceStatus) {
      ClearanceStatus.cleared => (AppColors.cleared, 'CLEARED'),
      ClearanceStatus.pendingClearance => (AppColors.pendingClearance, 'PENDING'),
      ClearanceStatus.flagged => (AppColors.flagged, 'FLAGGED'),
    };

    return PortalCard(
      lift: false,
      accent: color,
      margin: EdgeInsets.only(bottom: last ? 0 : density.gap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: StatusTint.surface(context, color),
                child: Icon(Icons.badge, color: StatusTint.onTint(context, color)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(result.fullName, style: theme.textTheme.titleMedium),
                    Text(result.workerCode, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          StatusPill(label: label, color: color),
          const SizedBox(height: 8),
          Text(
            'Confirmed incidents: ${result.confirmedIncidentCount}',
            style: theme.textTheme.bodyMedium,
          ),
          Text(
            'Details stay private to the worker\'s own station.',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: _loadingHistoryWorkerId == result.workerId
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : TextButton.icon(
                    onPressed: () => _showHistory(result),
                    icon: const Icon(Icons.history, size: 16),
                    label: const Text('Station history'),
                  ),
          ),
        ],
      ),
    );
  }
}
