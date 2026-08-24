import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/resource.dart';
import 'supabase_service.dart';

/// Downloadable resources library (checklists, floor-price schedule PDFs).
/// The `resources` storage bucket is public, and writes are restricted to
/// WASA admins by the resources_admin_write storage policy -- see
/// supabase/patch_tier1_tier2_features.sql.
class ResourceService {
  ResourceService(this._supabase);

  final SupabaseService _supabase;

  Future<List<Resource>> fetchResources() async {
    final rows = await _supabase.client.from('resources').select().order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows).map(Resource.fromMap).toList();
  }

  Future<void> uploadResource({
    required String title,
    required String category,
    required Uint8List bytes,
    required String fileExtension,
  }) async {
    final userId = _supabase.client.auth.currentUser!.id;
    final path = '${DateTime.now().microsecondsSinceEpoch}_${title.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_')}.$fileExtension';
    await _supabase.client.storage.from('resources').uploadBinary(path, bytes, fileOptions: const FileOptions(upsert: true));
    final url = _supabase.client.storage.from('resources').getPublicUrl(path);
    await _supabase.client.from('resources').insert({
      'title': title,
      'category': category,
      'storage_path': path,
      'file_url': url,
      'uploaded_by': userId,
    });
  }

  Future<void> deleteResource(Resource resource) async {
    await _supabase.client.storage.from('resources').remove([resource.storagePath]);
    await _supabase.client.from('resources').delete().eq('id', resource.id);
  }
}
