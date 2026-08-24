import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// Uploads for the three public photo buckets (avatars, station-photos,
/// bulletin-images) -- unlike permit-documents/worker-credentials, these
/// buckets are public (public=true), so there's no signed-URL step: the
/// public CDN URL (getPublicUrl) is usable directly and permanently.
///
/// Takes raw bytes rather than a `dart:io` File -- File doesn't exist on
/// Flutter web at all, and FilePicker's `withData: true` already returns
/// bytes uniformly on every platform (native included), so this isn't a
/// web-only special case, just the one signature that works everywhere.
class PhotoService {
  PhotoService(this._supabase);

  final SupabaseService _supabase;

  Future<String> _uploadAndGetPublicUrl({
    required String bucket,
    required String path,
    required Uint8List bytes,
  }) async {
    await _supabase.client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    return _supabase.client.storage.from(bucket).getPublicUrl(path);
  }

  /// Path convention: {profile_id}/avatar.{ext} -- matches the
  /// avatars_self_write storage policy (0009_rls.sql).
  Future<String> uploadAvatar({required String profileId, required Uint8List bytes, required String fileExtension}) {
    return _uploadAndGetPublicUrl(bucket: 'avatars', path: '$profileId/avatar.$fileExtension', bytes: bytes);
  }

  /// Path convention: {station_id}/photo.{ext} -- matches the
  /// station_photos_owner_write storage policy (0009_rls.sql).
  Future<String> uploadStationPhoto({required String stationId, required Uint8List bytes, required String fileExtension}) {
    return _uploadAndGetPublicUrl(bucket: 'station-photos', path: '$stationId/photo.$fileExtension', bytes: bytes);
  }

  /// Bulletin posts don't have an id until they're inserted, and non-admin
  /// posters only have an INSERT policy on `bulletins` (no UPDATE) -- so the
  /// image must be uploaded to a unique, self-contained path BEFORE the
  /// post is created, then its URL passed straight into the insert.
  /// Path convention: {profile_id}/{timestamp}_image.{ext} -- profile_id is
  /// its own folder segment (matches avatars/station-photos so the
  /// bulletin_images_poster_write storage policy can cast it to uuid);
  /// uniqueness across a poster's own images comes from the filename.
  /// Returns the storage path alongside the public URL so the caller can
  /// clean the file up (deleteBulletinImage) if post creation fails after
  /// a successful upload -- otherwise a failed/retried post leaves an
  /// orphaned file behind with nothing ever referencing it.
  Future<({String path, String publicUrl})> uploadBulletinImage({
    required String authorProfileId,
    required Uint8List bytes,
    required String fileExtension,
  }) async {
    final uniquePath = '$authorProfileId/${DateTime.now().microsecondsSinceEpoch}_image.$fileExtension';
    final publicUrl = await _uploadAndGetPublicUrl(bucket: 'bulletin-images', path: uniquePath, bytes: bytes);
    return (path: uniquePath, publicUrl: publicUrl);
  }

  Future<void> deleteBulletinImage(String path) {
    return _supabase.client.storage.from('bulletin-images').remove([path]);
  }
}
