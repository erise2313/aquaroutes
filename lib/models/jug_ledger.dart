/// Mirrors the `jug_balances` view and `jug_settlements` table
/// (supabase/migrations/0007_jug_clearinghouse.sql).
enum JugType { slim5gal, round5gal }

JugType jugTypeFromString(String value) {
  return value == 'round_5gal' ? JugType.round5gal : JugType.slim5gal;
}

String jugTypeToString(JugType type) => type == JugType.round5gal ? 'round_5gal' : 'slim_5gal';

enum SettlementStatus { proposed, confirmed, rejected }

SettlementStatus settlementStatusFromString(String value) {
  switch (value) {
    case 'confirmed':
      return SettlementStatus.confirmed;
    case 'rejected':
      return SettlementStatus.rejected;
    default:
      return SettlementStatus.proposed;
  }
}

/// A net balance between two stations for one jug type: `holderStationId`
/// currently holds `netQty` of `owner Station`'s jugs.
class JugBalance {
  final String holderStationId;
  final String ownerStationId;
  final JugType jugType;
  final int netQty;

  const JugBalance({
    required this.holderStationId,
    required this.ownerStationId,
    required this.jugType,
    required this.netQty,
  });

  factory JugBalance.fromMap(Map<String, dynamic> map) {
    return JugBalance(
      holderStationId: map['holder_station_id'] as String,
      ownerStationId: map['owner_station_id'] as String,
      jugType: jugTypeFromString(map['jug_type'] as String),
      netQty: map['net_qty'] as int,
    );
  }
}

class JugSettlement {
  final String id;
  final String holderStationId;
  final String ownerStationId;
  final JugType jugType;
  final int quantity;
  final SettlementStatus status;

  const JugSettlement({
    required this.id,
    required this.holderStationId,
    required this.ownerStationId,
    required this.jugType,
    required this.quantity,
    required this.status,
  });

  factory JugSettlement.fromMap(Map<String, dynamic> map) {
    return JugSettlement(
      id: map['id'] as String,
      holderStationId: map['holder_station_id'] as String,
      ownerStationId: map['owner_station_id'] as String,
      jugType: jugTypeFromString(map['jug_type'] as String),
      quantity: map['quantity'] as int,
      status: settlementStatusFromString(map['status'] as String? ?? 'proposed'),
    );
  }
}
