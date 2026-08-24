import 'permit.dart';

/// Mirrors the `workers` and `worker_incidents` tables
/// (supabase/migrations/0005_workers.sql). Worker codes follow
/// GW-WRK-YYYY-XXXX, generated server-side.
enum ClearanceStatus { pendingClearance, cleared, flagged }

ClearanceStatus clearanceStatusFromString(String value) {
  switch (value) {
    case 'cleared':
      return ClearanceStatus.cleared;
    case 'flagged':
      return ClearanceStatus.flagged;
    default:
      return ClearanceStatus.pendingClearance;
  }
}

enum IncidentStatus { pendingReview, confirmedFlag, dismissed }

IncidentStatus incidentStatusFromString(String value) {
  switch (value) {
    case 'confirmed_flag':
      return IncidentStatus.confirmedFlag;
    case 'dismissed':
      return IncidentStatus.dismissed;
    default:
      return IncidentStatus.pendingReview;
  }
}

class Worker {
  final String id;
  // Nullable: a worker between stations (left/removed, not re-linked yet)
  // has no current station -- their identity/clearance/incident history
  // persists regardless.
  final String? stationId;
  final String? profileId;
  final String workerCode;
  final String fullName;
  final String roleTitle;
  final String? phoneNumber;
  final String? vehiclePlate;
  final int? jugCapacity;
  final ClearanceStatus clearanceStatus;
  final String? qrPayload;

  const Worker({
    required this.id,
    this.stationId,
    this.profileId,
    required this.workerCode,
    required this.fullName,
    required this.roleTitle,
    this.phoneNumber,
    this.vehiclePlate,
    this.jugCapacity,
    required this.clearanceStatus,
    this.qrPayload,
  });

  factory Worker.fromMap(Map<String, dynamic> map) {
    return Worker(
      id: map['id'] as String,
      stationId: map['station_id'] as String?,
      profileId: map['profile_id'] as String?,
      workerCode: map['worker_code'] as String,
      fullName: map['full_name'] as String,
      phoneNumber: map['phone_number'] as String?,
      roleTitle: map['role_title'] as String? ?? 'driver/helper',
      vehiclePlate: map['vehicle_plate'] as String?,
      jugCapacity: map['jug_capacity'] as int?,
      clearanceStatus: clearanceStatusFromString(map['clearance_status'] as String? ?? 'pending_clearance'),
      qrPayload: map['qr_payload'] as String?,
    );
  }
}

class WorkerIncident {
  final String id;
  final String workerId;
  final String reportedByProfileId;
  final String incidentType;
  final String description;
  final double? amountInvolved;
  final IncidentStatus status;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  const WorkerIncident({
    required this.id,
    required this.workerId,
    required this.reportedByProfileId,
    required this.incidentType,
    required this.description,
    this.amountInvolved,
    required this.status,
    required this.createdAt,
    this.resolvedAt,
  });

  factory WorkerIncident.fromMap(Map<String, dynamic> map) {
    return WorkerIncident(
      id: map['id'] as String,
      workerId: map['worker_id'] as String,
      reportedByProfileId: map['reported_by_profile_id'] as String,
      incidentType: map['incident_type'] as String,
      description: map['description'] as String,
      amountInvolved: (map['amount_involved'] as num?)?.toDouble(),
      status: incidentStatusFromString(map['status'] as String? ?? 'pending_review'),
      createdAt: DateTime.parse(map['created_at'] as String),
      resolvedAt: map['resolved_at'] == null ? null : DateTime.parse(map['resolved_at'] as String),
    );
  }
}

/// Mirrors the `worker_credentials` table -- reuses [PermitStatus] since
/// the two document-review flows (station permits, worker credentials)
/// share the exact same missing/pending_review/approved/rejected shape.
enum WorkerCredentialType { governmentId, driversLicense }

WorkerCredentialType workerCredentialTypeFromString(String value) {
  return value == 'drivers_license' ? WorkerCredentialType.driversLicense : WorkerCredentialType.governmentId;
}

String workerCredentialTypeToString(WorkerCredentialType type) {
  return type == WorkerCredentialType.driversLicense ? 'drivers_license' : 'government_id';
}

String workerCredentialTypeLabel(WorkerCredentialType type) {
  return type == WorkerCredentialType.driversLicense ? "Driver's License" : 'Government-Issued ID';
}

class WorkerCredential {
  final String id;
  final String workerId;
  final WorkerCredentialType credentialType;
  final String? storagePath;
  final PermitStatus status;
  final String? rejectionReason;

  const WorkerCredential({
    required this.id,
    required this.workerId,
    required this.credentialType,
    this.storagePath,
    required this.status,
    this.rejectionReason,
  });

  factory WorkerCredential.fromMap(Map<String, dynamic> map) {
    return WorkerCredential(
      id: map['id'] as String,
      workerId: map['worker_id'] as String,
      credentialType: workerCredentialTypeFromString(map['credential_type'] as String),
      storagePath: map['storage_path'] as String?,
      status: permitStatusFromString(map['status'] as String? ?? 'missing'),
      rejectionReason: map['rejection_reason'] as String?,
    );
  }
}

/// Mirrors the `worker_station_history` table -- the record of which
/// station(s) a worker has been affiliated with, over time.
enum StationHistoryStatus { active, left, removed }

StationHistoryStatus stationHistoryStatusFromString(String value) {
  switch (value) {
    case 'left':
      return StationHistoryStatus.left;
    case 'removed':
      return StationHistoryStatus.removed;
    default:
      return StationHistoryStatus.active;
  }
}

class WorkerStationHistoryEntry {
  final String stationName;
  final DateTime joinedAt;
  final DateTime? leftAt;
  final StationHistoryStatus status;

  const WorkerStationHistoryEntry({
    required this.stationName,
    required this.joinedAt,
    this.leftAt,
    required this.status,
  });

  factory WorkerStationHistoryEntry.fromMap(Map<String, dynamic> map) {
    return WorkerStationHistoryEntry(
      stationName: map['station_name'] as String,
      joinedAt: DateTime.parse(map['joined_at'] as String),
      leftAt: map['left_at'] == null ? null : DateTime.parse(map['left_at'] as String),
      status: stationHistoryStatusFromString(map['status'] as String? ?? 'active'),
    );
  }
}

/// Result row from the hire_check_search() RPC -- deliberately a summary
/// only (status + confirmed incident count), never incident descriptions
/// or amounts from another station.
class HireCheckResult {
  final String workerId;
  final String workerCode;
  final String fullName;
  final ClearanceStatus clearanceStatus;
  final int confirmedIncidentCount;

  const HireCheckResult({
    required this.workerId,
    required this.workerCode,
    required this.fullName,
    required this.clearanceStatus,
    required this.confirmedIncidentCount,
  });

  factory HireCheckResult.fromMap(Map<String, dynamic> map) {
    return HireCheckResult(
      workerId: map['worker_id'] as String,
      workerCode: map['worker_code'] as String,
      fullName: map['full_name'] as String,
      clearanceStatus: clearanceStatusFromString(map['clearance_status'] as String? ?? 'pending_clearance'),
      confirmedIncidentCount: (map['confirmed_incident_count'] as num?)?.toInt() ?? 0,
    );
  }
}
