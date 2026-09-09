import '../models/web_content.dart';
import 'supabase_service.dart';

/// Admin-editable content for the website's static pages (About, FAQ,
/// Contact, For Station Owners, How Accreditation Works, Jug Clearinghouse
/// Explainer) -- and the same in-app info screens (supabase/patch_website_content_cms.sql).
/// Follows BulletinService's exact shape: public fetches read straight from
/// the table (RLS already scopes writes to wasa_admin), admin writes go
/// through this service rather than the UI hand-rolling raw Supabase calls.
class WebContentService {
  WebContentService(this._supabase);

  final SupabaseService _supabase;

  Future<List<WebPageSection>> fetchSections(String pageKey) async {
    final rows = await _supabase.client.from('web_page_sections').select().eq('page_key', pageKey).order('sort_order');
    return rows.map((r) => WebPageSection.fromMap(r)).toList();
  }

  Future<List<WebContentItem>> fetchItems(String pageKey, String itemKey) async {
    final rows = await _supabase.client
        .from('web_content_items')
        .select()
        .eq('page_key', pageKey)
        .eq('item_key', itemKey)
        .order('sort_order');
    return rows.map((r) => WebContentItem.fromMap(r)).toList();
  }

  Future<List<WebFaqEntry>> fetchFaqs() async {
    final rows = await _supabase.client.from('web_faq_entries').select().order('sort_order');
    return rows.map((r) => WebFaqEntry.fromMap(r)).toList();
  }

  /// wasa_admin only (enforced by RLS). Upserts on (page_key, section_key)
  /// -- pass the existing id when editing in place, omit it to create.
  Future<void> upsertSection({
    String? id,
    required String pageKey,
    required String sectionKey,
    String? title,
    required String body,
    int sortOrder = 0,
    required String updatedByProfileId,
  }) {
    final data = {
      if (id != null) 'id': id,
      'page_key': pageKey,
      'section_key': sectionKey,
      'title': title,
      'body': body,
      'sort_order': sortOrder,
      'updated_by': updatedByProfileId,
      'updated_at': DateTime.now().toIso8601String(),
    };
    return _supabase.client.from('web_page_sections').upsert(data, onConflict: 'page_key,section_key');
  }

  /// wasa_admin only. Pass an existing [id] to update that item in place;
  /// omit it to insert a new one into the (page_key, item_key) list.
  Future<void> upsertItem({
    String? id,
    required String pageKey,
    required String itemKey,
    String? icon,
    required String title,
    required String body,
    int sortOrder = 0,
    required String updatedByProfileId,
  }) {
    final data = {
      if (id != null) 'id': id,
      'page_key': pageKey,
      'item_key': itemKey,
      'icon': icon,
      'title': title,
      'body': body,
      'sort_order': sortOrder,
      'updated_by': updatedByProfileId,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (id != null) {
      return _supabase.client.from('web_content_items').update(data).eq('id', id);
    }
    return _supabase.client.from('web_content_items').insert(data);
  }

  Future<void> deleteItem(String id) {
    return _supabase.client.from('web_content_items').delete().eq('id', id);
  }

  Future<void> upsertFaq({
    String? id,
    required String question,
    required String answer,
    int sortOrder = 0,
    required String updatedByProfileId,
  }) {
    final data = {
      if (id != null) 'id': id,
      'question': question,
      'answer': answer,
      'sort_order': sortOrder,
      'updated_by': updatedByProfileId,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (id != null) {
      return _supabase.client.from('web_faq_entries').update(data).eq('id', id);
    }
    return _supabase.client.from('web_faq_entries').insert(data);
  }

  Future<void> deleteFaq(String id) {
    return _supabase.client.from('web_faq_entries').delete().eq('id', id);
  }
}
