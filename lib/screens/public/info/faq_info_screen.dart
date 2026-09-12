import 'package:flutter/material.dart';

import '../../../models/web_content.dart';
import '../../../services/supabase_service.dart';
import '../../../services/web_content_service.dart';
import '../../../widgets/error_state.dart';
import '../../../widgets/portal/portal.dart';
import '../../../utils/error_text.dart';

/// In-app mirror of faq_screen.dart -- same admin-editable content
/// (web_faq_entries), plain ExpansionTile list instead of the website's
/// styled accordion.
class FaqInfoScreen extends StatefulWidget {
  const FaqInfoScreen({super.key});

  @override
  State<FaqInfoScreen> createState() => _FaqInfoScreenState();
}

class _FaqInfoScreenState extends State<FaqInfoScreen> {
  final _webContentService = WebContentService(SupabaseService.instance);

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
      final faqs = await _webContentService.fetchFaqs();
      if (mounted) setState(() { _faqs = faqs; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Could not load the FAQ. ${describeError(e)}'; _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FAQ')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              // An empty FAQ used to render a blank page with no explanation.
              : _faqs.isEmpty
              ? const PortalEmptyState(
                  icon: Icons.help_outline,
                  title: 'No questions published yet',
                  message: 'The association adds answers to common questions here. Check back soon.',
                )
              : ListView.builder(
                  padding: PortalDensity.of(context).pagePadding,
                  itemCount: _faqs.length,
                  itemBuilder: (context, index) => _buildFaqCard(_faqs[index]),
                ),
    );
  }

  Widget _buildFaqCard(WebFaqEntry faq) {
    final theme = Theme.of(context);

    return PortalCard(
      lift: false,
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        title: Text(faq.question, style: theme.textTheme.titleMedium),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            faq.answer,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.5),
          ),
        ],
      ),
    );
  }
}
