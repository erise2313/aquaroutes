import 'package:flutter/material.dart';

import '../../../models/web_content.dart';
import '../../../services/supabase_service.dart';
import '../../../services/web_content_service.dart';
import '../../../widgets/error_state.dart';
import '../../auth/registration_screen.dart';

const _benefitIcons = {
  'verified': Icons.verified,
  'security': Icons.security,
  'price_change': Icons.price_change,
  'swap_horiz': Icons.swap_horiz,
};

/// In-app mirror of for_station_owners_screen.dart -- same admin-editable
/// content (web_content_items page 'for_station_owners' item 'benefits';
/// web_page_sections section 'requirements_summary').
class ForStationOwnersInfoScreen extends StatefulWidget {
  const ForStationOwnersInfoScreen({super.key});

  @override
  State<ForStationOwnersInfoScreen> createState() => _ForStationOwnersInfoScreenState();
}

class _ForStationOwnersInfoScreenState extends State<ForStationOwnersInfoScreen> {
  final _webContentService = WebContentService(SupabaseService.instance);

  bool _isLoading = true;
  String? _error;
  List<WebContentItem> _benefits = [];
  String _requirementsSummary = '';

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
      final benefits = await _webContentService.fetchItems('for_station_owners', 'benefits');
      final sections = await _webContentService.fetchSections('for_station_owners');
      if (mounted) {
        setState(() {
          _benefits = benefits;
          _requirementsSummary = sections.where((s) => s.sectionKey == 'requirements_summary').map((s) => s.body).firstOrNull ?? '';
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
      appBar: AppBar(title: const Text('For Station Owners')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text('Why Join', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    for (final b in _benefits)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(_benefitIcons[b.icon] ?? Icons.check_circle, color: Colors.blue.shade700),
                          title: Text(b.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(b.body),
                        ),
                      ),
                    const SizedBox(height: 20),
                    const Text('What You\'ll Need', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(_requirementsSummary, style: const TextStyle(color: Colors.grey, height: 1.4)),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const RegistrationScreen())),
                      child: const Text('Register Your Station'),
                    ),
                  ],
                ),
    );
  }
}
