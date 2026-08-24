import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/app_colors.dart';
import '../../models/worker.dart';
import '../../services/supabase_service.dart';
import '../../services/worker_service.dart';

/// Station-scoped fleet roster. Fixes the most severe bug found in the old
/// app: the previous version streamed ALL rows where role='driver' with no
/// station filter at all, so every station owner could see every driver in
/// the system. This now scopes to the owner's own station_id, and Postgres
/// RLS (0009_rls.sql) enforces the same boundary server-side even if this
/// client-side filter is ever dropped again.
class DriverManagementScreen extends StatefulWidget {
  const DriverManagementScreen({super.key});

  @override
  State<DriverManagementScreen> createState() => _DriverManagementScreenState();
}

class _DriverManagementScreenState extends State<DriverManagementScreen> {
  final _supabase = Supabase.instance.client;
  final _workerService = WorkerService(SupabaseService.instance);

  String? _stationId;
  bool _isLoading = true;
  int _idleThresholdMinutes = 5;

  @override
  void initState() {
    super.initState();
    _resolveStation();
  }

  Future<void> _resolveStation() async {
    final userId = _supabase.auth.currentUser!.id;
    final station = await _supabase.from('water_stations').select('id').eq('owner_profile_id', userId).maybeSingle();
    if (mounted) {
      setState(() {
        _stationId = station?['id'] as String?;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Fleet Management & Tracking"),
        actions: [
          IconButton(
            icon: const Icon(Icons.timer_outlined),
            tooltip: 'Set Custom Idle Threshold',
            onPressed: _showIdleThresholdDialog,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _stationId == null
              ? const Center(child: Text('No station linked to this account.'))
              : StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _workerService.watchStationWorkers(_stationId!),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                    final workers = snapshot.data!.map((m) => Worker.fromMap(m)).toList();

                    if (workers.isEmpty) {
                      return const Center(child: Text('No drivers registered yet.'));
                    }

                    return ListView.builder(
                      itemCount: workers.length,
                      itemBuilder: (context, index) => _buildDriverCard(workers[index]),
                    );
                  },
                ),
    );
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    if (phoneNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number saved for this driver.')),
      );
      return;
    }
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      debugPrint('Could not launch phone dialer for $phoneNumber');
    }
  }

  Widget _buildDriverCard(Worker worker) {
    final (clearanceColor, clearanceLabel) = switch (worker.clearanceStatus) {
      ClearanceStatus.cleared => (AppColors.cleared, 'CLEARED'),
      ClearanceStatus.pendingClearance => (AppColors.pendingClearance, 'PENDING'),
      ClearanceStatus.flagged => (AppColors.flagged, 'FLAGGED'),
    };

    return FutureBuilder<Map<String, dynamic>?>(
      future: _workerService.fetchDriverState(worker.id),
      builder: (context, snapshot) {
        final driverState = snapshot.data;
        final bool isActive = driverState?['is_active'] as bool? ?? false;
        final lastUpdatedRaw = driverState?['last_updated'] as String?;
        final lastUpdated = lastUpdatedRaw == null ? null : DateTime.tryParse(lastUpdatedRaw);
        // Real staleness check: only flag idle if the driver is ON-DUTY and
        // their last GPS ping is older than the threshold -- not just a
        // one-off low-speed reading (the old check).
        final isIdle = isActive &&
            lastUpdated != null &&
            DateTime.now().difference(lastUpdated) > Duration(minutes: _idleThresholdMinutes);

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            leading: Icon(
              Icons.directions_car,
              color: !isActive
                  ? Colors.grey
                  : isIdle
                      ? Colors.orange
                      : Colors.green,
            ),
            title: Row(
              children: [
                Text(worker.fullName),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: clearanceColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                  child: Text(clearanceLabel, style: TextStyle(color: clearanceColor, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Plate: ${worker.vehiclePlate ?? 'N/A'} · ${worker.workerCode}"),
                Text(isActive ? 'ON DUTY' : 'OFF DUTY', style: TextStyle(color: isActive ? Colors.green : Colors.grey, fontSize: 12)),
                if (isIdle)
                  Text(
                    "Idle (no update for over $_idleThresholdMinutes mins)",
                    style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.phone, color: Colors.green),
                  tooltip: 'Call Driver',
                  onPressed: () => _makePhoneCall(worker.phoneNumber ?? ''),
                ),
                if (isIdle)
                  IconButton(
                    icon: const Icon(Icons.notifications_active, color: Colors.orange),
                    tooltip: 'Send Idle Reminder',
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Idle reminder sent to ${worker.fullName}.'),
                          backgroundColor: Colors.orange.shade700,
                        ),
                      );
                    },
                  ),
              ],
            ),
            onTap: () => _showEditDialog(worker),
          ),
        );
      },
    );
  }

  void _showIdleThresholdDialog() {
    final controller = TextEditingController(text: _idleThresholdMinutes.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Configure Idle Timer Limit"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Set how long a driver can go without a GPS update before flagged as idle:"),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Threshold (Minutes)"),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _idleThresholdMinutes = int.tryParse(controller.text) ?? 5;
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Idle limit updated to $_idleThresholdMinutes minutes.')),
              );
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(Worker worker) {
    final plateController = TextEditingController(text: worker.vehiclePlate);
    final capController = TextEditingController(text: worker.jugCapacity?.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Configure ${worker.fullName}"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: plateController, decoration: const InputDecoration(labelText: "Plate Number")),
            TextField(controller: capController, decoration: const InputDecoration(labelText: "Capacity (Jugs)")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              await _workerService.updateWorker(worker.id, {
                'vehicle_plate': plateController.text,
                'jug_capacity': int.tryParse(capController.text),
              });
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }
}
