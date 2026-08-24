import '../models/worker.dart';
import 'supabase_service.dart';

/// Worker Security Registry CRUD + incident filing
/// (supabase/migrations/0005_workers.sql). Owners are scoped to their own
/// station's workers by RLS; only a WASA admin can resolve incidents.
class WorkerService {
  WorkerService(this._supabase);

  final SupabaseService _supabase;

  Stream<List<Map<String, dynamic>>> watchStationWorkers(String stationId) {
    // driver_states is embedded via its FK to workers(id) for live
    // is_active/current_speed/last_updated -- PostgREST resolves this
    // automatically since driver_states.worker_id references workers.id.
    return _supabase.client
        .from('workers')
        .stream(primaryKey: ['id'])
        .eq('station_id', stationId);
  }

  Future<Map<String, dynamic>?> fetchDriverState(String workerId) async {
    return _supabase.client.from('driver_states').select().eq('worker_id', workerId).maybeSingle();
  }

  Future<void> addWorker({
    required String stationId,
    required String fullName,
    String? phoneNumber,
    String? vehiclePlate,
    int? jugCapacity,
  }) {
    return _supabase.client.from('workers').insert({
      'station_id': stationId,
      'full_name': fullName,
      'phone_number': phoneNumber,
      'vehicle_plate': vehiclePlate,
      'jug_capacity': jugCapacity,
    });
  }

  Future<void> updateWorker(String workerId, Map<String, dynamic> fields) {
    return _supabase.client.from('workers').update(fields).eq('id', workerId);
  }

  Future<void> fileIncident({
    required String workerId,
    required String reportedByProfileId,
    required String incidentType,
    required String description,
    double? amountInvolved,
  }) {
    return _supabase.client.from('worker_incidents').insert({
      'worker_id': workerId,
      'reported_by_profile_id': reportedByProfileId,
      'incident_type': incidentType,
      'description': description,
      'amount_involved': amountInvolved,
    });
  }

  Future<List<WorkerIncident>> fetchIncidentsForWorker(String workerId) async {
    final rows = await _supabase.client
        .from('worker_incidents')
        .select()
        .eq('worker_id', workerId)
        .order('created_at', ascending: false);
    return rows.map((r) => WorkerIncident.fromMap(r)).toList();
  }

  /// Driver self-service: leave the current station (e.g. quitting). Nulls
  /// workers.station_id/memberships.station_id and closes the active
  /// worker_station_history row -- all inside the driver_leave_station() RPC
  /// (0005_workers.sql), not a raw table update.
  Future<void> leaveStation() {
    return _supabase.client.rpc('driver_leave_station');
  }

  /// Driver self-service: switch to a different station via a new invite
  /// code. Blocked server-side if the worker is currently 'flagged' -- see
  /// driver_switch_station() (0005_workers.sql).
  Future<void> switchStation(String inviteCode) {
    return _supabase.client.rpc('driver_switch_station', params: {'p_invite_code': inviteCode});
  }

  /// Station owner: remove a worker from their own roster. Only succeeds if
  /// the caller currently owns that worker's station (owner_remove_worker()
  /// RPC enforces this, not just client-side trust).
  Future<void> removeWorkerFromRoster(String workerId) {
    return _supabase.client.rpc('owner_remove_worker', params: {'p_worker_id': workerId});
  }

  /// Hire Check: cross-station search by name or worker code. Returns only
  /// a summary (clearance status + confirmed incident count) -- never
  /// incident descriptions/amounts from another station.
  Future<List<HireCheckResult>> hireCheckSearch(String query) async {
    final rows = await _supabase.client.rpc('hire_check_search', params: {'p_query': query});
    return List<Map<String, dynamic>>.from(rows as List).map((r) => HireCheckResult.fromMap(r)).toList();
  }

  Future<List<WorkerStationHistoryEntry>> fetchStationHistory(String workerId) async {
    final rows = await _supabase.client.rpc('hire_check_station_history', params: {'p_worker_id': workerId});
    return List<Map<String, dynamic>>.from(rows as List).map((r) => WorkerStationHistoryEntry.fromMap(r)).toList();
  }
}
