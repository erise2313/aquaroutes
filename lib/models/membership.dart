/// Mirrors the `memberships` table (supabase/migrations/0003_memberships.sql)
/// and the `app_role` enum. Replaces the old flat `user_profiles.role` string
/// entirely -- a role is now a scoped membership row, not a column on the
/// user's identity.
enum AppRole { wasaAdmin, stationOwner, driver, publicConsumer }

AppRole appRoleFromString(String value) {
  switch (value) {
    case 'wasa_admin':
      return AppRole.wasaAdmin;
    case 'station_owner':
      return AppRole.stationOwner;
    case 'driver':
      return AppRole.driver;
    default:
      return AppRole.publicConsumer;
  }
}

String appRoleToString(AppRole role) {
  switch (role) {
    case AppRole.wasaAdmin:
      return 'wasa_admin';
    case AppRole.stationOwner:
      return 'station_owner';
    case AppRole.driver:
      return 'driver';
    case AppRole.publicConsumer:
      return 'public_consumer';
  }
}

class Membership {
  final String id;
  final String profileId;
  final String associationId;
  final AppRole role;
  final String? stationId;
  final String status;

  const Membership({
    required this.id,
    required this.profileId,
    required this.associationId,
    required this.role,
    this.stationId,
    required this.status,
  });

  bool get isActive => status == 'active';

  factory Membership.fromMap(Map<String, dynamic> map) {
    return Membership(
      id: map['id'] as String,
      profileId: map['profile_id'] as String,
      associationId: map['association_id'] as String,
      role: appRoleFromString(map['role'] as String),
      stationId: map['station_id'] as String?,
      status: map['status'] as String? ?? 'active',
    );
  }
}
