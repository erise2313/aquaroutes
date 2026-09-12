import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/app_colors.dart';
import '../../models/worker.dart';
import '../../services/supabase_service.dart';
import '../../services/worker_service.dart';
import '../../widgets/portal/portal.dart';

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

  // Cached per-worker so the FutureBuilder in _buildDriverCard doesn't
  // create (and await) a brand new future on every rebuild -- previously
  // any change to any driver's row re-emitted the whole watchStationWorkers
  // stream, rebuilding every card and snapping every driver's status back
  // to a blank/loading state simultaneously while the futures re-resolved.
  final Map<String, Future<Map<String, dynamic>?>> _driverStateFutures = {};
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _resolveStation();
    // driver_states changes far more often than the workers table (a GPS
    // ping every ~10m moved) but isn't itself streamed here -- a periodic
    // clear-and-refetch keeps ON DUTY/idle status reasonably fresh without
    // re-fetching (and flickering) on every unrelated workers-row change.
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() => _driverStateFutures.clear());
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _resolveStation() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
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
    final density = PortalDensity.of(context);

    return Scaffold(
      body: Column(
        children: [
          PortalPageHeader(
            eyebrow: 'Fleet management',
            title: 'Track & Manage Drivers',
            subtitle: 'Vehicle details, duty status, and who has gone quiet',
            actions: [
              IconButton(
                icon: const Icon(Icons.timer_outlined),
                tooltip: 'Set custom idle threshold',
                onPressed: _showIdleThresholdDialog,
              ),
            ],
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _stationId == null
                ? const PortalEmptyState(
                    icon: Icons.storefront_outlined,
                    title: 'No station linked to this account',
                    message: 'Your account is not linked to a water station, so it has no fleet.',
                  )
                : StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _workerService.watchStationWorkers(_stationId!),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                      final workers = snapshot.data!.map((m) => Worker.fromMap(m)).toList();

                      if (workers.isEmpty) {
                        return const PortalEmptyState(
                          icon: Icons.local_shipping_outlined,
                          title: 'No drivers registered yet',
                          message: 'Share your station invite code from the Worker Registry so a driver '
                              'can register themselves at your station.',
                        );
                      }

                      return ListView.builder(
                        padding: density.pagePadding,
                        itemCount: workers.length,
                        itemBuilder: (context, index) =>
                            _buildDriverCard(workers[index], last: index == workers.length - 1, density: density),
                      );
                    },
                  ),
          ),
        ],
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

  Widget _buildDriverCard(Worker worker, {required bool last, required PortalDensity density}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final (clearanceColor, clearanceLabel) = switch (worker.clearanceStatus) {
      ClearanceStatus.cleared => (AppColors.cleared, 'CLEARED'),
      ClearanceStatus.pendingClearance => (AppColors.pendingClearance, 'PENDING'),
      ClearanceStatus.flagged => (AppColors.flagged, 'FLAGGED'),
    };

    return FutureBuilder<Map<String, dynamic>?>(
      future: _driverStateFutures.putIfAbsent(worker.id, () => _workerService.fetchDriverState(worker.id)),
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

        // Duty state drives the card's edge: grey off duty, amber gone quiet,
        // green out working.
        final dutyTone = !isActive
            ? AppColors.inkMuted
            : isIdle
                ? AppColors.pendingClearance
                : AppColors.cleared;

        return PortalCard(
          onTap: () => _showEditDialog(worker),
          accent: dutyTone,
          margin: EdgeInsets.only(bottom: last ? 0 : density.gap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(color: StatusTint.surface(context, dutyTone), shape: BoxShape.circle),
                    child: Icon(Icons.directions_car, color: StatusTint.onTint(context, dutyTone), size: 21),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(worker.fullName, style: theme.textTheme.titleMedium),
                        Text(
                          "Plate: ${worker.vehiclePlate ?? 'N/A'} · ${worker.workerCode}",
                          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // A Wrap bounds its children, so these labels wrap rather than
              // running off the card at large system text.
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  StatusPill(label: isActive ? 'ON DUTY' : 'OFF DUTY', color: dutyTone),
                  StatusPill(label: clearanceLabel, color: clearanceColor),
                  if (isIdle)
                    StatusPill(
                      label: 'IDLE OVER $_idleThresholdMinutes MIN',
                      color: AppColors.pendingClearance,
                      icon: Icons.warning_amber_rounded,
                    ),
                ],
              ),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 4,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.phone, size: 16),
                    label: const Text('Call driver'),
                    onPressed: () => _makePhoneCall(worker.phoneNumber ?? ''),
                  ),
                  if (isIdle)
                    TextButton.icon(
                      icon: const Icon(Icons.notifications_active, size: 16),
                      label: const Text('Send reminder'),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Idle reminder sent to ${worker.fullName}.')),
                        );
                      },
                    ),
                ],
              ),
            ],
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
