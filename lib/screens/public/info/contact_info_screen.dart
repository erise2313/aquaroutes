import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../services/supabase_service.dart';
import '../../../services/web_content_service.dart';
import '../../../widgets/error_state.dart';
import '../../../utils/error_text.dart';

/// In-app mirror of contact_screen.dart -- same admin-editable content
/// (web_page_sections, page 'contact').
class ContactInfoScreen extends StatefulWidget {
  const ContactInfoScreen({super.key});

  @override
  State<ContactInfoScreen> createState() => _ContactInfoScreenState();
}

class _ContactInfoScreenState extends State<ContactInfoScreen> {
  final _webContentService = WebContentService(SupabaseService.instance);

  bool _isLoading = true;
  String? _error;
  Map<String, String> _sections = {};

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
      final sections = await _webContentService.fetchSections('contact');
      if (mounted) {
        setState(() {
          _sections = {for (final s in sections) s.sectionKey: s.body};
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = 'Could not load this page. ${describeError(e)}'; _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = _sections['email'] ?? 'contact@gentriwasa.example';

    return Scaffold(
      appBar: AppBar(title: const Text('Contact')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _contactRow(Icons.location_on_outlined, _sections['address'] ?? '[Placeholder] Association Office Address, General Trias, Cavite'),
                            const Divider(height: 24),
                            _contactRow(Icons.access_time, _sections['hours'] ?? '[Placeholder] Office Hours: Monday-Friday, 8:00 AM - 5:00 PM'),
                            const Divider(height: 24),
                            InkWell(
                              onTap: () => launchUrl(Uri.parse('mailto:$email')),
                              child: _contactRow(Icons.email_outlined, email, isLink: true),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _contactRow(IconData icon, String text, {bool isLink = false}) {
    return Row(
      children: [
        Icon(icon, color: Colors.blue.shade700),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 15, decoration: isLink ? TextDecoration.underline : null, color: isLink ? Colors.blue.shade700 : null),
          ),
        ),
      ],
    );
  }
}
