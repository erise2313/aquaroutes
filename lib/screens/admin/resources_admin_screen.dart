import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../constants/admin_theme.dart';
import '../../models/resource.dart';
import '../../services/resource_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/admin_page_header.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/error_state.dart';
import '../../widgets/skeleton_loader.dart';
import '../../utils/error_text.dart';

/// WASA admin upload/manage screen for the public resources library
/// (permit checklists, floor-price schedule, etc.) -- reuses the same
/// PDF-capable FilePicker pattern already proven in permit_vault_screen.dart.
class ResourcesAdminScreen extends StatefulWidget {
  const ResourcesAdminScreen({super.key});

  @override
  State<ResourcesAdminScreen> createState() => _ResourcesAdminScreenState();
}

class _ResourcesAdminScreenState extends State<ResourcesAdminScreen> {
  final _resourceService = ResourceService(SupabaseService.instance);

  bool _isLoading = true;
  String? _error;
  List<Resource> _resources = [];

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
      final resources = await _resourceService.fetchResources();
      if (mounted) setState(() { _resources = resources; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Could not load resources. ${describeError(e)}'; _isLoading = false; });
    }
  }

  Future<void> _uploadFlow() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
    final picked = result?.files.single;
    if (picked == null || picked.bytes == null || !mounted) return;

    final titleController = TextEditingController(text: picked.name.replaceAll('.pdf', ''));
    String category = 'general';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Upload Resource'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'general', child: Text('General')),
                  DropdownMenuItem(value: 'permits', child: Text('Permits')),
                  DropdownMenuItem(value: 'pricing', child: Text('Pricing')),
                ],
                onChanged: (v) => setDialogState(() => category = v ?? 'general'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Upload')),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _resourceService.uploadResource(
        title: titleController.text.trim().isEmpty ? picked.name : titleController.text.trim(),
        category: category,
        bytes: picked.bytes!,
        fileExtension: picked.extension ?? 'pdf',
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Resource uploaded.')));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed. ${describeError(e)}')));
    }
  }

  Future<void> _delete(Resource resource) async {
    final confirmed = await showConfirmDialog(context, title: 'Delete Resource', message: 'Delete "${resource.title}"? This cannot be undone.');
    if (confirmed != true) return;
    try {
      await _resourceService.deleteResource(resource);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed. ${describeError(e)}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(onPressed: _uploadFlow, icon: const Icon(Icons.upload_file), label: const Text('Upload')),
      // AdminPageHeader rather than a plain AppBar: this screen and Events
      // were the only two in the portal wearing Material's default bar, so
      // opening them from the dashboard dropped you out of the navy/gold
      // portal into a generic one. The header supplies its own back button.
      body: Column(
        children: [
          const AdminPageHeader(title: 'Resources Library', subtitle: 'Downloads published on the public website'),
          Expanded(
            child: _isLoading
                ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList(count: 4))
                : _error != null
                ? ErrorState(message: _error!, onRetry: _load)
                : _resources.isEmpty
                ? _emptyState()
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _resources.length,
                    itemBuilder: (context, index) {
                      final r = _resources[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(Icons.picture_as_pdf_outlined, color: Colors.red),
                          title: Text(r.title),
                          subtitle: Text('${r.category} · ${DateFormat('MMM d, yyyy').format(r.createdAt)}'),
                          trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), tooltip: 'Delete resource', onPressed: () => _delete(r)),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open_outlined, size: 56, color: AdminTheme.inkNavy.withValues(alpha: 0.25)),
            const SizedBox(height: 16),
            const Text('No resources uploaded yet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AdminTheme.inkNavy)),
            const SizedBox(height: 8),
            Text(
              'Anything you upload here appears on the public website\'s Resources page for members to download.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AdminTheme.inkNavy.withValues(alpha: 0.6)),
            ),
          ],
        ),
      ),
    );
  }
}
