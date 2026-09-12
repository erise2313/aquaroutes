import 'package:flutter/material.dart';

import '../../../constants/app_colors.dart';
import '../../../models/web_content.dart';
import '../../../services/supabase_service.dart';
import '../../../services/web_content_service.dart';
import '../../../widgets/error_state.dart';
import '../../../widgets/portal/portal.dart';
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
                  padding: PortalDensity.of(context).pagePadding,
                  children: [
                    // Was a blue.shade50 fill with an amber rule -- a pale
                    // block that stayed pale in dark mode.
                    StatusCallout(
                      accent: AppColors.primary,
                      icon: Icons.swap_horiz,
                      title: 'How jug settlement works',
                      message: _intro,
                    ),
                    SizedBox(height: PortalSection.gapAfter(context)),
                    for (var i = 0; i < _steps.length; i++) _stepTile(i + 1, _steps[i].title, _steps[i].body),
                  ],
                ),
    );
  }

  Widget _stepTile(int number, String title, String description) {
    final theme = Theme.of(context);

    return PortalCard(
      lift: false,
      margin: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: AppColors.primary,
            child: Text('$number', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
