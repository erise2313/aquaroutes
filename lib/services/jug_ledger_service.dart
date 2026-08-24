import '../models/jug_ledger.dart';
import 'supabase_service.dart';

/// Inter-Station Jug Clearinghouse (supabase/migrations/0007_jug_clearinghouse.sql).
/// Settlement confirm/reject go through the confirm_jug_settlement()/
/// reject_jug_settlement() RPCs (not direct table writes) since those
/// atomically write the offsetting ledger entry and enforce that only the
/// receiving station can confirm.
class JugLedgerService {
  JugLedgerService(this._supabase);

  final SupabaseService _supabase;

  /// Balances involving the given station, either as holder or owner.
  Future<List<JugBalance>> fetchBalancesForStation(String stationId) async {
    final rows = await _supabase.client
        .from('jug_balances')
        .select()
        .or('holder_station_id.eq.$stationId,owner_station_id.eq.$stationId');
    return rows.map((r) => JugBalance.fromMap(r)).toList();
  }

  Future<List<JugSettlement>> fetchSettlementsForStation(String stationId) async {
    final rows = await _supabase.client
        .from('jug_settlements')
        .select()
        .or('holder_station_id.eq.$stationId,owner_station_id.eq.$stationId')
        .order('created_at', ascending: false);
    return rows.map((r) => JugSettlement.fromMap(r)).toList();
  }

  Future<void> recordJugTransfer({
    required String holderStationId,
    required String ownerStationId,
    required JugType jugType,
    required int quantity,
    required String recordedByProfileId,
    String? relatedOrderId,
  }) {
    return _supabase.client.from('jug_ledger_entries').insert({
      'holder_station_id': holderStationId,
      'owner_station_id': ownerStationId,
      'jug_type': jugTypeToString(jugType),
      'quantity': quantity,
      'related_order_id': relatedOrderId,
      'recorded_by': recordedByProfileId,
    });
  }

  Future<void> proposeSettlement({
    required String holderStationId,
    required String ownerStationId,
    required JugType jugType,
    required int quantity,
    required String proposedByProfileId,
  }) {
    return _supabase.client.from('jug_settlements').insert({
      'holder_station_id': holderStationId,
      'owner_station_id': ownerStationId,
      'jug_type': jugTypeToString(jugType),
      'quantity': quantity,
      'proposed_by': proposedByProfileId,
    });
  }

  Future<void> confirmSettlement(String settlementId) {
    return _supabase.client.rpc('confirm_jug_settlement', params: {'p_settlement_id': settlementId});
  }

  Future<void> rejectSettlement(String settlementId) {
    return _supabase.client.rpc('reject_jug_settlement', params: {'p_settlement_id': settlementId});
  }

  Future<List<Map<String, dynamic>>> fetchOtherStations(String excludingStationId) async {
    final rows = await _supabase.client.from('water_stations').select('id, station_name').neq('id', excludingStationId);
    return List<Map<String, dynamic>>.from(rows);
  }
}
