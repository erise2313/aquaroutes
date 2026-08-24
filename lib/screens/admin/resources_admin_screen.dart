import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/resource.dart';
import '../../services/resource_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/error_state.dart';

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
      if (mounted) setState(() { _error = 'Could not load resources: $e'; _isLoading = false; });
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    }
  }

  Future<void> _delete(Resource resource) async {
    final confirmed = await showConfirmDialog(context, title: 'Delete Resource', message: 'Delete "${resource.title}"? This cannot be undone.');
    if (confirmed != true) return;
    try {
      await _resourceService.deleteResource(resource);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Resources Library')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _uploadFlow, icon: const Icon(Icons.upload_file), label: const Text('Upload')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? ErrorState(message: _error!, onRetry: _load)
          : _resources.isEmpty
          ? const Center(child: Text('No resources uploaded yet.', style: TextStyle(color: Colors.grey)))
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
    );
  }
}
