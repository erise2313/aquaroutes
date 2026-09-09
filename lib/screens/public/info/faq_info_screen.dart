import 'package:flutter/material.dart';

import '../../../models/web_content.dart';
import '../../../services/supabase_service.dart';
import '../../../services/web_content_service.dart';
import '../../../widgets/error_state.dart';

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
      if (mounted) setState(() { _error = 'Could not load the FAQ: $e'; _isLoading = false; });
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
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _faqs.length,
                  itemBuilder: (context, index) {
                    final faq = _faqs[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ExpansionTile(
                        title: Text(faq.question, style: const TextStyle(fontWeight: FontWeight.w600)),
                        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        expandedCrossAxisAlignment: CrossAxisAlignment.start,
                        children: [Text(faq.answer, style: const TextStyle(height: 1.4))],
                      ),
                    );
                  },
                ),
    );
  }
}
