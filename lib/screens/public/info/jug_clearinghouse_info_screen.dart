import 'package:flutter/material.dart';

import '../../../models/web_content.dart';
import '../../../services/supabase_service.dart';
import '../../../services/web_content_service.dart';
import '../../../widgets/error_state.dart';
import '../../../utils/error_text.dart';

/// In-app mirror of jug_clearinghouse_explainer_screen.dart -- same
/// admin-editable content (web_page_sections page 'jug_clearinghouse'
/// section 'intro'; web_content_items item 'steps').
class JugClearinghouseInfoScreen extends StatefulWidget {
  const JugClearinghouseInfoScreen({super.key});

  @override
  State<JugClearinghouseInfoScreen> createState() => _JugClearinghouseInfoScreenState();
}

class _JugClearinghouseInfoScreenState extends State<JugClearinghouseInfoScreen> {
  final _webContentService = WebContentService(SupabaseService.instance);

  bool _isLoading = true;
  String? _error;
  String _intro = '';
  List<WebContentItem> _steps = [];

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
      final sections = await _webContentService.fetchSections('jug_clearinghouse');
      final steps = await _webContentService.fetchItems('jug_clearinghouse', 'steps');
      if (mounted) {
        setState(() {
          _intro = sections.where((s) => s.sectionKey == 'intro').map((s) => s.body).firstOrNull ?? '';
          _steps = steps;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = 'Could not load this page. ${describeError(e)}'; _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Jug Clearinghouse')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10), border: Border(left: BorderSide(color: Colors.amber.shade700, width: 4))),
                      child: Text(_intro, style: const TextStyle(height: 1.5)),
                    ),
                    const SizedBox(height: 24),
                    for (var i = 0; i < _steps.length; i++) _stepTile(i + 1, _steps[i].title, _steps[i].body),
                  ],
                ),
    );
  }

  Widget _stepTile(int number, String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
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
