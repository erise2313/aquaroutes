import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../constants/app_colors.dart';
import '../../models/worker.dart';
import '../../services/supabase_service.dart';
import '../../services/worker_service.dart';

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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _showHistory(HireCheckResult result) async {
    final history = await _workerService.fetchStationHistory(result.workerId);
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${result.fullName} -- Station History', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (history.isEmpty) Text('No station history on record.', style: TextStyle(color: Colors.grey.shade700)),
            ...history.map((h) {
              final range = h.leftAt == null
                  ? '${DateFormat('MMM yyyy').format(h.joinedAt)} -- present'
                  : '${DateFormat('MMM yyyy').format(h.joinedAt)} -- ${DateFormat('MMM yyyy').format(h.leftAt!)}';
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  h.status == StationHistoryStatus.active ? Icons.store : Icons.store_outlined,
                  color: h.status == StationHistoryStatus.active ? Colors.green : Colors.grey,
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
    return Scaffold(
      appBar: AppBar(title: const Text('Hire Check')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Search a worker by name or worker code before hiring them.',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: 'Name or Worker Code',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.search),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isSearching ? null : _search,
                  child: _isSearching
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Search'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: !_hasSearched
                  ? const SizedBox.shrink()
                  : _results.isEmpty
                      ? Center(child: Text('No matching workers found.', style: TextStyle(color: Colors.grey.shade700)))
                      : ListView.builder(
                          itemCount: _results.length,
                          itemBuilder: (context, index) => _buildResultCard(_results[index]),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(HireCheckResult result) {
    final (color, label) = switch (result.clearanceStatus) {
      ClearanceStatus.cleared => (AppColors.cleared, 'CLEARED'),
      ClearanceStatus.pendingClearance => (AppColors.pendingClearance, 'PENDING'),
      ClearanceStatus.flagged => (AppColors.flagged, 'FLAGGED'),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.15), child: Icon(Icons.badge, color: color)),
        title: Text(result.fullName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(result.workerCode),
            Text('Confirmed incidents: ${result.confirmedIncidentCount}'),
          ],
        ),
        isThreeLine: true,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
              child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11)),
            ),
            TextButton(onPressed: () => _showHistory(result), child: const Text('History', style: TextStyle(fontSize: 12))),
          ],
        ),
      ),
    );
  }
}
