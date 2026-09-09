import 'package:flutter/material.dart';

import '../../../models/web_content.dart';
import '../../../services/permit_service.dart';
import '../../../services/supabase_service.dart';
import '../../../services/web_content_service.dart';
import '../../../widgets/error_state.dart';

/// In-app mirror of how_accreditation_works_screen.dart -- same
/// admin-editable content (web_content_items page
/// 'how_accreditation_works'; permit_type_labels for the checklist, the
/// same shared source permit_vault_screen.dart/permit_review_screen.dart
/// read from).
class HowAccreditationWorksInfoScreen extends StatefulWidget {
  const HowAccreditationWorksInfoScreen({super.key});

  @override
  State<HowAccreditationWorksInfoScreen> createState() => _HowAccreditationWorksInfoScreenState();
}

class _HowAccreditationWorksInfoScreenState extends State<HowAccreditationWorksInfoScreen> {
  final _webContentService = WebContentService(SupabaseService.instance);
  final _permitService = PermitService(SupabaseService.instance);

  bool _isLoading = true;
  String? _error;
  List<WebContentItem> _steps = [];
  List<PermitTypeLabel> _permitLabels = [];

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
      final steps = await _webContentService.fetchItems('how_accreditation_works', 'steps');
      final labels = await _permitService.fetchPermitLabels();
      if (mounted) {
        setState(() {
          _steps = steps;
          _permitLabels = labels;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = 'Could not load this page: $e'; _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('How Accreditation Works')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (var i = 0; i < _steps.length; i++) _stepTile(i + 1, _steps[i].title, _steps[i].body),
                    const SizedBox(height: 16),
                    const Text('Required Documents', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    for (final p in _permitLabels)
                      Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        child: ListTile(
                          leading: const Icon(Icons.description_outlined, color: Colors.blueGrey),
                          title: Text(p.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(p.conditionNote),
                        ),
                      ),
                  ],
                ),
    );
  }

  Widget _stepTile(int number, String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(radius: 14, backgroundColor: Colors.blue.shade700, child: Text('$number', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(description, style: const TextStyle(color: Colors.grey, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
