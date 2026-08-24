import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/worker.dart';
import 'supabase_service.dart';

/// Worker credential vault: Supabase Storage upload + `worker_credentials`
/// table CRUD (supabase/migrations/0005_workers.sql). Mirrors
/// permit_service.dart's pattern exactly -- the two required documents
/// (government_id, drivers_license) are auto-created by a Postgres trigger
/// whenever a worker row is inserted, and approving both flips the worker
/// to 'cleared' automatically (unless already 'flagged').
///
/// Unlike station permits, personal ID documents are NOT owner-visible --
/// only the worker themselves and wasa_admin can read/write the actual
/// file (see the storage RLS policies in 0009_rls.sql); a station owner
/// can still see the credential *status* via fetchWorkerCredentials, just
/// never the document itself.
class WorkerCredentialService {
  WorkerCredentialService(this._supabase);

  final SupabaseService _supabase;

  static const _bucket = 'worker-credentials';

  Future<List<WorkerCredential>> fetchWorkerCredentials(String workerId) async {
    final rows = await _supabase.client.from('worker_credentials').select().eq('worker_id', workerId);
    return rows.map((r) => WorkerCredential.fromMap(r)).toList();
  }

  /// Uploads a document for one credential slot and marks it pending_review.
  /// Path convention: {worker_id}/{credential_type}.{ext} -- matches the
  /// storage RLS policy in 0009_rls.sql. Takes raw bytes (not a `dart:io`
  /// File, which doesn't exist on web) -- see photo_service.dart's class
  /// doc comment for why this is the right signature on every platform.
  Future<void> uploadCredentialDocument({
    required String workerId,
    required WorkerCredentialType credentialType,
    required Uint8List bytes,
    required String fileExtension,
  }) async {
    final path = '$workerId/${workerCredentialTypeToString(credentialType)}.$fileExtension';

    await _supabase.client.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );

    await _supabase.client.from('worker_credentials').update({
      'storage_path': path,
      'status': 'pending_review',
      'uploaded_at': DateTime.now().toIso8601String(),
    }).match({'worker_id': workerId, 'credential_type': workerCredentialTypeToString(credentialType)});
  }

  /// Signed URL so wasa_admin can actually view the uploaded document
  /// before approving/rejecting -- mirrors permit_service.dart's
  /// getSignedUrl (previously the equivalent for credentials didn't exist
  /// at all, so admin was reviewing blind).
  Future<String> getSignedUrl(String storagePath) {
    return _supabase.client.storage.from(_bucket).createSignedUrl(storagePath, 3600);
  }

  /// wasa_admin only (enforced by RLS): approve/reject a submitted credential.
  Future<void> reviewCredential({
    required String credentialId,
    required bool approve,
    required String reviewedByProfileId,
    String? rejectionReason,
  }) {
    return _supabase.client.from('worker_credentials').update({
      'status': approve ? 'approved' : 'rejected',
      'reviewed_by': reviewedByProfileId,
      'reviewed_at': DateTime.now().toIso8601String(),
      'rejection_reason': approve ? null : rejectionReason,
    }).eq('id', credentialId);
  }
}
