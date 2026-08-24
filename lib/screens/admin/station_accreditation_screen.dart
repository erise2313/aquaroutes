import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../widgets/confirm_dialog.dart';
import 'permit_review_screen.dart';

/// Association-wide list of all stations, for WASA admins to drill into
/// each one's Permit Vault. Unlike station-owner/driver screens, admins are
/// not scoped to a single station_id -- RLS (0009_rls.sql) grants
/// auth_has_role('wasa_admin') full read access across every station.
/// Also where admin deactivates/reactivates a station -- reversible,
/// hides it from the public map/ordering without deleting anything (see
/// water_stations.is_active, 0002_stations.sql).
class StationAccreditationScreen extends StatefulWidget {
  const StationAccreditationScreen({super.key});

  @override
  State<StationAccreditationScreen> createState() => _StationAccreditationScreenState();
}

class _StationAccreditationScreenState extends State<StationAccreditationScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _stations = [];

  @override
  void initState() {
    super.initState();
    _fetchStations();
  }

  Future<void> _fetchStations() async {
    setState(() => _isLoading = true);
    final rows = await _supabase
        .from('water_stations')
        .select('id, station_name, station_address, is_accredited, is_colorum_verified, is_active')
        .order('station_name');
    if (mounted) {
      setState(() {
        _stations = List<Map<String, dynamic>>.from(rows);
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> station) async {
    final isActive = station['is_active'] as bool? ?? true;
    final stationName = station['station_name'] as String? ?? 'this station';

    final confirmed = await showConfirmDialog(
      context,
      title: isActive ? 'Deactivate Station?' : 'Reactivate Station?',
      message: isActive
          ? '$stationName will disappear from the public map and can no longer accept new orders. This is fully reversible and all its history/permits/orders stay intact.'
          : '$stationName will become visible on the public map and able to accept orders again.',
      confirmLabel: isActive ? 'Deactivate' : 'Reactivate',
      isDestructive: isActive,
    );
    if (!confirmed) return;

    try {
      await _supabase.from('water_stations').update({'is_active': !isActive}).eq('id', station['id'] as String);
      _fetchStations();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Station Accreditation')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchStations,
              child: ListView.builder(
                itemCount: _stations.length,
                itemBuilder: (context, index) {
                  final station = _stations[index];
                  final isAccredited = station['is_accredited'] as bool? ?? false;
                  final isVerified = station['is_colorum_verified'] as bool? ?? false;
                  final isActive = station['is_active'] as bool? ?? true;

                  return Opacity(
                    opacity: isActive ? 1.0 : 0.55,
                    child: ListTile(
                      leading: Icon(
                        isAccredited ? Icons.verified : Icons.hourglass_top,
                        color: isAccredited ? Colors.green : Colors.amber.shade800,
                      ),
                      title: Row(
                        children: [
                          Flexible(child: Text(station['station_name'] ?? 'Unnamed Station')),
                          if (!isActive) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(6)),
                              child: const Text('Deactivated', style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text(
                        '${station['station_address'] ?? ''}\n'
                        '${isVerified ? 'Colorum Verified' : 'Not yet verified'}',
                      ),
                      isThreeLine: true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(isActive ? Icons.toggle_on : Icons.toggle_off, color: isActive ? Colors.green : Colors.grey, size: 32),
                            tooltip: isActive ? 'Deactivate' : 'Reactivate',
                            onPressed: () => _toggleActive(station),
                          ),
                          const Icon(Icons.arrow_forward_ios, size: 16),
                        ],
                      ),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => PermitReviewScreen(
                              stationId: station['id'] as String,
                              stationName: station['station_name'] as String? ?? 'Station',
                            ),
                          ),
                        );
                        _fetchStations();
                      },
                    ),
                  );
                },
              ),
            ),
    );
  }
}
