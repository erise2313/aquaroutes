import '../models/permit.dart';

/// Mirrors `web_page_sections` -- a single admin-editable text block on a
/// website page (e.g. Contact's address/hours/email, an intro paragraph).
/// Identified by (pageKey, sectionKey); read/write via WebContentService.
class WebPageSection {
  final String id;
  final String pageKey;
  final String sectionKey;
  final String? title;
  final String body;
  final int sortOrder;

  const WebPageSection({
    required this.id,
    required this.pageKey,
    required this.sectionKey,
    this.title,
    required this.body,
    required this.sortOrder,
  });

  factory WebPageSection.fromMap(Map<String, dynamic> map) {
    return WebPageSection(
      id: map['id'] as String,
      pageKey: map['page_key'] as String,
      sectionKey: map['section_key'] as String,
      title: map['title'] as String?,
      body: map['body'] as String,
      sortOrder: map['sort_order'] as int? ?? 0,
    );
  }
}

/// Mirrors `web_content_items` -- one entry in an admin-editable ordered
/// list on a page (e.g. About's "What WASA Does" bullets, For Station
/// Owners' benefit cards, a process-steps list). Grouped by (pageKey,
/// itemKey); ordered by sortOrder.
class WebContentItem {
  final String id;
  final String pageKey;
  final String itemKey;
  final String? icon;
  final String title;
  final String body;
  final int sortOrder;

  const WebContentItem({
    required this.id,
    required this.pageKey,
    required this.itemKey,
    this.icon,
    required this.title,
    required this.body,
    required this.sortOrder,
  });

  factory WebContentItem.fromMap(Map<String, dynamic> map) {
    return WebContentItem(
      id: map['id'] as String,
      pageKey: map['page_key'] as String,
      itemKey: map['item_key'] as String,
      icon: map['icon'] as String?,
      title: map['title'] as String,
      body: map['body'] as String,
      sortOrder: map['sort_order'] as int? ?? 0,
    );
  }
}

/// Mirrors `web_faq_entries` -- one admin-editable Q&A pair on the FAQ page.
class WebFaqEntry {
  final String id;
  final String question;
  final String answer;
  final int sortOrder;

  const WebFaqEntry({
    required this.id,
    required this.question,
    required this.answer,
    required this.sortOrder,
  });

  factory WebFaqEntry.fromMap(Map<String, dynamic> map) {
    return WebFaqEntry(
      id: map['id'] as String,
      question: map['question'] as String,
      answer: map['answer'] as String,
      sortOrder: map['sort_order'] as int? ?? 0,
    );
  }
}

/// Mirrors `permit_type_labels` -- the single admin-editable source for a
/// permit type's display name and requirement note, shared by the Permit
/// Vault, Permit Review, and the "How Accreditation Works" website page
/// (previously three independent hardcoded copies).
class PermitTypeLabel {
  final PermitType permitType;
  final String label;
  final String conditionNote;
  final int sortOrder;

  const PermitTypeLabel({
    required this.permitType,
    required this.label,
    required this.conditionNote,
    required this.sortOrder,
  });

  factory PermitTypeLabel.fromMap(Map<String, dynamic> map) {
    return PermitTypeLabel(
      permitType: permitTypeFromString(map['permit_type'] as String),
      label: map['label'] as String,
      conditionNote: map['condition_note'] as String,
      sortOrder: map['sort_order'] as int? ?? 0,
    );
  }
}
