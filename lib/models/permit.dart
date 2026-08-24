/// Mirrors the `permits` table (supabase/migrations/0004_permits.sql).
/// `alkaline_tech_cert`/`alkaline_water_test` are only `isRequired` when the
/// owning station's `offered_water_types` includes 'alkaline' -- enforced by
/// a Postgres trigger, not client logic.
enum PermitType { businessPermit, sanitaryPermit, fdaLicense, alkalineTechCert, alkalineWaterTest }

enum PermitStatus { missing, pendingReview, approved, rejected }

PermitType permitTypeFromString(String value) {
  return PermitType.values.firstWhere(
    (t) => _permitTypeToString(t) == value,
    orElse: () => PermitType.businessPermit,
  );
}

String _permitTypeToString(PermitType type) {
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

PermitStatus permitStatusFromString(String value) {
  switch (value) {
    case 'pending_review':
      return PermitStatus.pendingReview;
    case 'approved':
      return PermitStatus.approved;
    case 'rejected':
      return PermitStatus.rejected;
    default:
      return PermitStatus.missing;
  }
}

class Permit {
  final String id;
  final String stationId;
  final PermitType permitType;
  final bool isRequired;
  final String? storagePath;
  final PermitStatus status;
  final String? reviewedBy;
  final String? rejectionReason;
  // Optional -- not every permit type has a hard renewal date, so an admin
  // may leave this unset when approving.
  final DateTime? expiryDate;

  const Permit({
    required this.id,
    required this.stationId,
    required this.permitType,
    required this.isRequired,
    this.storagePath,
    required this.status,
    this.reviewedBy,
    this.rejectionReason,
    this.expiryDate,
  });

  /// True once expiry is within 30 days (or already past) -- drives the
  /// "Renewal due" badge in permit_review_screen.dart.
  bool get isRenewalDueSoon {
    if (expiryDate == null) return false;
    return expiryDate!.difference(DateTime.now()).inDays <= 30;
  }

  factory Permit.fromMap(Map<String, dynamic> map) {
    return Permit(
      id: map['id'] as String,
      stationId: map['station_id'] as String,
      permitType: permitTypeFromString(map['permit_type'] as String),
      isRequired: map['is_required'] as bool? ?? true,
      storagePath: map['storage_path'] as String?,
      status: permitStatusFromString(map['status'] as String? ?? 'missing'),
      reviewedBy: map['reviewed_by'] as String?,
      rejectionReason: map['rejection_reason'] as String?,
      expiryDate: map['expiry_date'] == null ? null : DateTime.parse(map['expiry_date'] as String),
    );
  }
}
