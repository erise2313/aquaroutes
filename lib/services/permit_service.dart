import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/permit.dart';
import 'supabase_service.dart';

/// Permit Vault: Supabase Storage upload + `permits` table CRUD
/// (supabase/migrations/0004_permits.sql). Which permits are `isRequired`
/// (in particular the two alkaline documents) is driven entirely by a
/// Postgres trigger reacting to `water_stations.offered_water_types` -- this
/// service does not decide that itself, only reads/writes what the DB says.
class PermitService {
  PermitService(this._supabase);

  final SupabaseService _supabase;

  static const _bucket = 'permit-documents';

  Future<List<Permit>> fetchStationPermits(String stationId) async {
    final rows = await _supabase.client.from('permits').select().eq('station_id', stationId);
    return rows.map((r) => Permit.fromMap(r)).toList();
  }

  /// Uploads a document for one permit slot and marks it pending_review.
  /// Path convention: {station_id}/{permit_type}.{ext} -- matches the
  /// storage RLS policy in 0009_rls.sql. Takes raw bytes (not a `dart:io`
  /// File, which doesn't exist on web) -- see photo_service.dart's class
  /// doc comment for why this is the right signature on every platform.
  Future<void> uploadPermitDocument({
    required String stationId,
    required PermitType permitType,
    required Uint8List bytes,
    required String fileExtension,
  }) async {
    final path = '$stationId/${_permitTypeSlug(permitType)}.$fileExtension';

    await _supabase.client.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );

    await _supabase.client.from('permits').update({
      'storage_path': path,
      'status': 'pending_review',
      'uploaded_at': DateTime.now().toIso8601String(),
    }).match({'station_id': stationId, 'permit_type': _permitTypeSlug(permitType)});
  }

  Future<String> getSignedUrl(String storagePath) {
    return _supabase.client.storage.from(_bucket).createSignedUrl(storagePath, 3600);
  }

  /// wasa_admin only (enforced by RLS): approve/reject a submitted permit.
  /// [expiryDate] is optional and only meaningful on approval -- not every
  /// permit type has a hard renewal date.
  Future<void> reviewPermit({
    required String permitId,
    required bool approve,
    required String reviewedByProfileId,
    String? rejectionReason,
    DateTime? expiryDate,
  }) {
    return _supabase.client.from('permits').update({
      'status': approve ? 'approved' : 'rejected',
      'reviewed_by': reviewedByProfileId,
      'reviewed_at': DateTime.now().toIso8601String(),
      'rejection_reason': approve ? null : rejectionReason,
      if (approve) 'expiry_date': expiryDate?.toIso8601String().split('T').first,
    }).eq('id', permitId);
  }

  String _permitTypeSlug(PermitType type) {
    switch (type) {
      case PermitType.businessPermit:
        return 'business_permit';
      case PermitType.sanitaryPermit:
        return 'sanitary_permit';
      case PermitType.fdaLicense:
        return 'fda_license';
      case PermitType.alkalineTechCert:
        return 'alkaline_tech_cert';
      case PermitType.alkalineWaterTest:
        return 'alkaline_water_test';
    }
  }
}
