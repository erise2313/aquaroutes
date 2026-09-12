import 'package:flutter/material.dart';
import 'package:aquaroute/widgets/dispose_with.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/admin_theme.dart';
import '../../models/web_content.dart';
import '../../services/permit_service.dart';
import '../../services/supabase_service.dart';
import '../../services/web_content_service.dart';
import '../../widgets/admin_page_header.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/error_state.dart';
import '../../widgets/skeleton_loader.dart';
import '../../utils/error_text.dart';

/// wasa_admin editor for the website's static-page content (About, FAQ,
/// Contact, For Station Owners, How Accreditation Works, Jug Clearinghouse
/// Explainer) and the shared permit type labels -- everything that used to
/// be hardcoded directly in the web/app widget trees with no way for
/// anyone but a developer to change it (supabase/patch_website_content_cms.sql).
/// A page picker on the left, one of three small reusable editors on the
/// right depending on what that page's content actually looks like
/// (single text blocks, an ordered card/step list, or Q&A pairs) -- same
/// CRUD-dialog pattern as bulletin_editor_screen.dart, not six bespoke
/// screens.
class WebsiteContentScreen extends StatefulWidget {
  const WebsiteContentScreen({super.key});

  @override
  State<WebsiteContentScreen> createState() => _WebsiteContentScreenState();
}

enum _ContentPage { about, faq, contact, forStationOwners, howAccreditationWorks, jugClearinghouse, permitLabels }

extension on _ContentPage {
  String get label => switch (this) {
        _ContentPage.about => 'About',
        _ContentPage.faq => 'FAQ',
        _ContentPage.contact => 'Contact',
        _ContentPage.forStationOwners => 'For Station Owners',
        _ContentPage.howAccreditationWorks => 'How Accreditation Works',
        _ContentPage.jugClearinghouse => 'Jug Clearinghouse',
        _ContentPage.permitLabels => 'Permit Checklist Labels',
      };
}

class _WebsiteContentScreenState extends State<WebsiteContentScreen> {
  _ContentPage _selected = _ContentPage.about;

  Widget _buildEditor(_ContentPage page) {
    // _SectionsEditor/_ItemsEditor return a plain (non-scrolling) Column so
    // they can be safely nested as list items inside _MultiEditor's own
    // ListView (nesting a scrollable in a scrollable needs unbounded
    // height and breaks) -- but the three pages that use either of them
    // standalone need to supply that scrolling themselves, or their
    // content would overflow instead of scrolling on a short viewport.
    // _FaqEditor/_PermitLabelsEditor/_MultiEditor already own a ListView,
    // so they pass through unwrapped.
    final content = switch (page) {
      _ContentPage.about => const _ItemsEditor(pageKey: 'about', itemKey: 'what_wasa_does', label: '"What WASA Does" bullets', showTitleField: false),
      _ContentPage.faq => const _FaqEditor(),
      _ContentPage.contact => const _SectionsEditor(pageKey: 'contact', sections: [
          (key: 'address', label: 'Office Address'),
          (key: 'hours', label: 'Office Hours'),
          (key: 'email', label: 'Contact Email'),
        ]),
      _ContentPage.forStationOwners => const _MultiEditor(children: [
          _ItemsEditor(pageKey: 'for_station_owners', itemKey: 'benefits', label: 'Benefit cards', showTitleField: true, showIconField: true),
          _SectionsEditor(pageKey: 'for_station_owners', sections: [(key: 'requirements_summary', label: '"What You\'ll Need" summary')]),
        ]),
      _ContentPage.howAccreditationWorks =>
        const _ItemsEditor(pageKey: 'how_accreditation_works', itemKey: 'steps', label: 'Process steps', showTitleField: true),
      _ContentPage.jugClearinghouse => const _MultiEditor(children: [
          _SectionsEditor(pageKey: 'jug_clearinghouse', sections: [(key: 'intro', label: 'Intro paragraph')]),
          _ItemsEditor(pageKey: 'jug_clearinghouse', itemKey: 'steps', label: 'Process steps', showTitleField: true),
        ]),
      _ContentPage.permitLabels => const _PermitLabelsEditor(),
    };

    final needsOwnScroll = page == _ContentPage.about || page == _ContentPage.contact || page == _ContentPage.howAccreditationWorks;
    if (!needsOwnScroll) return content;
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: content);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const AdminPageHeader(title: 'Website Content', subtitle: 'Edit what shows on the public site and in the app'),
        Expanded(
          child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 700;
          if (isWide) {
            return Row(
              children: [
                SizedBox(
                  width: 240,
                  child: Container(
                    color: AdminTheme.foam,
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      children: [
                        for (final page in _ContentPage.values) _buildPageTile(page),
                      ],
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: _buildEditor(_selected)),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  children: [
                    for (final page in _ContentPage.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(page.label),
                          selected: page == _selected,
                          onSelected: (_) => setState(() => _selected = page),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(child: _buildEditor(_selected)),
            ],
          );
        },
          ),
        ),
      ],
    );
  }

  Widget _buildPageTile(_ContentPage page) {
    final selected = page == _selected;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: selected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: selected ? Border(left: BorderSide(color: AdminTheme.sealGold, width: 4)) : null,
        boxShadow: selected ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6)] : null,
      ),
      child: ListTile(
        contentPadding: EdgeInsets.only(left: selected ? 12 : 16, right: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Text(
          page.label,
          style: TextStyle(fontWeight: selected ? FontWeight.bold : FontWeight.normal, color: AdminTheme.inkNavy),
        ),
        onTap: () => setState(() => _selected = page),
      ),
    );
  }
}

/// Stacks several editors vertically for a page whose content spans more
/// than one table (e.g. a benefit-card list plus a plain paragraph).
class _MultiEditor extends StatelessWidget {
  const _MultiEditor({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [for (final c in children) ...[c, const Divider(height: 32)]],
    );
  }
}

/// Editor for a fixed set of single-value text blocks (web_page_sections).
/// Always inline (no add/delete) -- the set of section keys for a page is
/// fixed by what that page's layout actually needs.
class _SectionsEditor extends StatefulWidget {
  const _SectionsEditor({required this.pageKey, required this.sections});

  final String pageKey;
  final List<({String key, String label})> sections;

  @override
  State<_SectionsEditor> createState() => _SectionsEditorState();
}

class _SectionsEditorState extends State<_SectionsEditor> {
  final _service = WebContentService(SupabaseService.instance);
  bool _isLoading = true;
  String? _error;
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String?> _existingIds = {};
  final Set<String> _saving = {};

  @override
  void initState() {
    super.initState();
    for (final s in widget.sections) {
      _controllers[s.key] = TextEditingController();
    }
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final rows = await _service.fetchSections(widget.pageKey);
      final byKey = {for (final r in rows) r.sectionKey: r};
      for (final s in widget.sections) {
        final existing = byKey[s.key];
        _controllers[s.key]!.text = existing?.body ?? '';
        _existingIds[s.key] = existing?.id;
      }
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) setState(() { _error = 'Could not load. ${describeError(e)}'; _isLoading = false; });
    }
  }

  Future<void> _save(String sectionKey) async {
    setState(() => _saving.add(sectionKey));
    try {
      await _service.upsertSection(
        id: _existingIds[sectionKey],
        pageKey: widget.pageKey,
        sectionKey: sectionKey,
        body: _controllers[sectionKey]!.text.trim(),
        updatedByProfileId: Supabase.instance.client.auth.currentUser!.id,
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved.')));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save. ${describeError(e)}')));
    } finally {
      if (mounted) setState(() => _saving.remove(sectionKey));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Padding(padding: EdgeInsets.all(16), child: SkeletonList(count: 4));
    if (_error != null) return ErrorState(message: _error!, onRetry: _load);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final s in widget.sections) ...[
          Text(s.label, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          TextField(controller: _controllers[s.key], maxLines: 3, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true)),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              onPressed: _saving.contains(s.key) ? null : () => _save(s.key),
              child: Text(_saving.contains(s.key) ? 'Saving…' : 'Save ${s.label}'),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ],
    );
  }
}

/// Editor for an admin-managed ordered list (web_content_items) -- add,
/// edit, delete, reorder via a numeric sort field. Same
/// dialog-with-Form-and-showConfirmDialog pattern as bulletin_editor_screen.dart.
class _ItemsEditor extends StatefulWidget {
  const _ItemsEditor({required this.pageKey, required this.itemKey, required this.label, this.showTitleField = true, this.showIconField = false});

  final String pageKey;
  final String itemKey;
  final String label;
  final bool showTitleField;
  final bool showIconField;

  @override
  State<_ItemsEditor> createState() => _ItemsEditorState();
}

class _ItemsEditorState extends State<_ItemsEditor> {
  final _service = WebContentService(SupabaseService.instance);
  bool _isLoading = true;
  String? _error;
  List<WebContentItem> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final items = await _service.fetchItems(widget.pageKey, widget.itemKey);
      if (mounted) setState(() { _items = items; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Could not load. ${describeError(e)}'; _isLoading = false; });
    }
  }

  void _showEditDialog({WebContentItem? editing}) {
    final titleController = TextEditingController(text: editing?.title ?? '');
    final bodyController = TextEditingController(text: editing?.body ?? '');
    final iconController = TextEditingController(text: editing?.icon ?? '');
    final sortController = TextEditingController(text: '${editing?.sortOrder ?? _items.length}');

    showDialog(
      context: context,
      // Controllers are created per dialog, so they're released when it
      // leaves the tree (see DisposeWith for why not on pop).
      builder: (context) => DisposeWith(
        notifiers: [titleController, bodyController, iconController, sortController],
        child: AlertDialog(
        title: Text(editing == null ? 'Add Entry' : 'Edit Entry'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.showIconField)
                TextField(controller: iconController, decoration: const InputDecoration(labelText: 'Icon key (optional)')),
              if (widget.showTitleField)
                TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Title')),
              TextField(controller: bodyController, maxLines: 4, decoration: const InputDecoration(labelText: 'Body')),
              TextField(controller: sortController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Order (lower shows first)')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final body = bodyController.text.trim();
              if (body.isEmpty) return;
              try {
                await _service.upsertItem(
                  id: editing?.id,
                  pageKey: widget.pageKey,
                  itemKey: widget.itemKey,
                  icon: iconController.text.trim().isEmpty ? null : iconController.text.trim(),
                  title: titleController.text.trim(),
                  body: body,
                  sortOrder: int.tryParse(sortController.text.trim()) ?? 0,
                  updatedByProfileId: Supabase.instance.client.auth.currentUser!.id,
                );
                if (context.mounted) Navigator.pop(context);
                await _load();
              } catch (e) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save. ${describeError(e)}')));
              }
            },
            child: Text(editing == null ? 'Add' : 'Save'),
          ),
        ],
        ),
      ),
    );
  }

  Future<void> _delete(WebContentItem item) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete Entry?',
      message: 'This removes it from the live page immediately.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (!confirmed) return;
    try {
      await _service.deleteItem(item.id);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Padding(padding: EdgeInsets.all(16), child: SkeletonList(count: 4));
    if (_error != null) return ErrorState(message: _error!, onRetry: _load);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(widget.label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            TextButton.icon(onPressed: () => _showEditDialog(), icon: const Icon(Icons.add), label: const Text('Add')),
          ],
        ),
        for (final item in _items)
          Card(
            child: ListTile(
              title: Text(item.title.isEmpty ? item.body : item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: item.title.isEmpty ? null : Text(item.body, maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () => _showEditDialog(editing: item),
              trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), tooltip: 'Delete', onPressed: () => _delete(item)),
            ),
          ),
      ],
    );
  }
}

/// Editor for web_faq_entries -- same add/edit/delete dialog pattern as
/// _ItemsEditor, kept separate since a Q&A pair has a different shape
/// (question + answer, no icon/title split).
class _FaqEditor extends StatefulWidget {
  const _FaqEditor();

  @override
  State<_FaqEditor> createState() => _FaqEditorState();
}

class _FaqEditorState extends State<_FaqEditor> {
  final _service = WebContentService(SupabaseService.instance);
  bool _isLoading = true;
  String? _error;
  List<WebFaqEntry> _faqs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final faqs = await _service.fetchFaqs();
      if (mounted) setState(() { _faqs = faqs; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Could not load. ${describeError(e)}'; _isLoading = false; });
    }
  }

  void _showEditDialog({WebFaqEntry? editing}) {
    final questionController = TextEditingController(text: editing?.question ?? '');
    final answerController = TextEditingController(text: editing?.answer ?? '');
    final sortController = TextEditingController(text: '${editing?.sortOrder ?? _faqs.length}');

    showDialog(
      context: context,
      builder: (context) => DisposeWith(
        notifiers: [questionController, answerController, sortController],
        child: AlertDialog(
        title: Text(editing == null ? 'Add FAQ' : 'Edit FAQ'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: questionController, decoration: const InputDecoration(labelText: 'Question')),
              TextField(controller: answerController, maxLines: 4, decoration: const InputDecoration(labelText: 'Answer')),
              TextField(controller: sortController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Order (lower shows first)')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final question = questionController.text.trim();
              final answer = answerController.text.trim();
              if (question.isEmpty || answer.isEmpty) return;
              try {
                await _service.upsertFaq(
                  id: editing?.id,
                  question: question,
                  answer: answer,
                  sortOrder: int.tryParse(sortController.text.trim()) ?? 0,
                  updatedByProfileId: Supabase.instance.client.auth.currentUser!.id,
                );
                if (context.mounted) Navigator.pop(context);
                await _load();
              } catch (e) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save. ${describeError(e)}')));
              }
            },
            child: Text(editing == null ? 'Add' : 'Save'),
          ),
        ],
        ),
      ),
    );
  }

  Future<void> _delete(WebFaqEntry faq) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete this FAQ?',
      message: 'This removes it from the live FAQ page immediately.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (!confirmed) return;
    try {
      await _service.deleteFaq(faq.id);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Padding(padding: EdgeInsets.all(16), child: SkeletonList(count: 4));
    if (_error != null) return ErrorState(message: _error!, onRetry: _load);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('FAQ Entries', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            TextButton.icon(onPressed: () => _showEditDialog(), icon: const Icon(Icons.add), label: const Text('Add')),
          ],
        ),
        for (final faq in _faqs)
          Card(
            child: ListTile(
              title: Text(faq.question, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(faq.answer, maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () => _showEditDialog(editing: faq),
              trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), tooltip: 'Delete', onPressed: () => _delete(faq)),
            ),
          ),
      ],
    );
  }
}

/// Editor for permit_type_labels -- fixed 10 rows (one per permit_type
/// enum value), edit-only, no add/delete since the row set is bound to
/// the enum. This is the single source permit_vault_screen.dart,
/// permit_review_screen.dart, and how_accreditation_works_screen.dart all
/// now read from.
class _PermitLabelsEditor extends StatefulWidget {
  const _PermitLabelsEditor();

  @override
  State<_PermitLabelsEditor> createState() => _PermitLabelsEditorState();
}

class _PermitLabelsEditorState extends State<_PermitLabelsEditor> {
  final _service = PermitService(SupabaseService.instance);
  bool _isLoading = true;
  String? _error;
  List<PermitTypeLabel> _labels = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final labels = await _service.fetchPermitLabels();
      if (mounted) setState(() { _labels = labels; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Could not load. ${describeError(e)}'; _isLoading = false; });
    }
  }

  void _showEditDialog(PermitTypeLabel label) {
    final labelController = TextEditingController(text: label.label);
    final noteController = TextEditingController(text: label.conditionNote);

    showDialog(
      context: context,
      builder: (context) => DisposeWith(
        notifiers: [labelController, noteController],
        child: AlertDialog(
        title: const Text('Edit Permit Label'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: labelController, decoration: const InputDecoration(labelText: 'Display name')),
              TextField(controller: noteController, maxLines: 3, decoration: const InputDecoration(labelText: 'Requirement note')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final newLabel = labelController.text.trim();
              final newNote = noteController.text.trim();
              if (newLabel.isEmpty || newNote.isEmpty) return;
              try {
                await _service.updatePermitLabel(
                  permitType: label.permitType,
                  label: newLabel,
                  conditionNote: newNote,
                  updatedByProfileId: Supabase.instance.client.auth.currentUser!.id,
                );
                if (context.mounted) Navigator.pop(context);
                await _load();
              } catch (e) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save. ${describeError(e)}')));
              }
            },
            child: const Text('Save'),
          ),
        ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Padding(padding: EdgeInsets.all(16), child: SkeletonList(count: 4));
    if (_error != null) return ErrorState(message: _error!, onRetry: _load);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Shared by the Permit Vault, Permit Review, and the "How Accreditation Works" page -- editing one updates all three.',
          style: TextStyle(color: Colors.grey, fontSize: 12.5),
        ),
        const SizedBox(height: 12),
        for (final label in _labels)
          Card(
            child: ListTile(
              title: Text(label.label),
              subtitle: Text(label.conditionNote, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _showEditDialog(label),
            ),
          ),
      ],
    );
  }
}
