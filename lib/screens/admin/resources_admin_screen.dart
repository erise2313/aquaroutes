import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../constants/app_colors.dart';
import '../../models/resource.dart';
import '../../services/resource_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/admin_page_header.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/error_state.dart';
import '../../widgets/portal/portal.dart';
import '../../widgets/skeleton_loader.dart';
import '../../utils/error_text.dart';
import '../../constants/admin_palette.dart';

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
          const AdminPageHeader(
            eyebrow: 'Content management',
            title: 'Resources Library',
            subtitle: 'Downloads published on the public website',
          ),
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
                    itemBuilder: (context, index) => _buildResourceCard(_resources[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildResourceCard(Resource resource) {
    final palette = AdminPalette.of(context);

    return PortalCard(
      lift: false,
      accent: AppColors.flagged,
      margin: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: StatusTint.surface(context, AppColors.flagged), shape: BoxShape.circle),
            child: Icon(Icons.picture_as_pdf_outlined, color: StatusTint.onTint(context, AppColors.flagged), size: 21),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(resource.title, style: TextStyle(fontWeight: FontWeight.w600, color: palette.ink)),
                const SizedBox(height: 2),
                Text(
                  '${resource.category} · ${DateFormat('MMM d, yyyy').format(resource.createdAt)}',
                  style: TextStyle(fontSize: 12.5, color: palette.inkMuted),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            color: AppColors.flagged,
            tooltip: 'Delete resource',
            onPressed: () => _delete(resource),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return const PortalEmptyState(
      icon: Icons.folder_open_outlined,
      title: 'No resources uploaded yet',
      message: 'Anything you upload here appears on the public website\'s Resources page for members to download.',
    );
  }
}
