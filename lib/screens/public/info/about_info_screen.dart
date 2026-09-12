import 'package:flutter/material.dart';

import '../../../constants/app_colors.dart';
import '../../../models/web_content.dart';
import '../../../services/supabase_service.dart';
import '../../../services/web_content_service.dart';
import '../../../widgets/error_state.dart';
import '../../../widgets/portal/portal.dart';
import '../../../utils/error_text.dart';

/// In-app mirror of about_screen.dart -- same admin-editable content
/// (web_content_items, page 'about'; live barangays table), plain
/// Material widgets instead of the website's WebTheme styling.
class AboutInfoScreen extends StatefulWidget {
  const AboutInfoScreen({super.key});

  @override
  State<AboutInfoScreen> createState() => _AboutInfoScreenState();
}

class _AboutInfoScreenState extends State<AboutInfoScreen> {
  final _webContentService = WebContentService(SupabaseService.instance);

  bool _isLoading = true;
  String? _error;
  List<WebContentItem> _whatWasaDoes = [];
  List<String> _barangays = [];

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
      final items = await _webContentService.fetchItems('about', 'what_wasa_does');
      final rows = await SupabaseService.instance.client.from('barangays').select('name').order('name');
      final barangays = List<Map<String, dynamic>>.from(rows).map((r) => r['name'] as String).toList();
      if (mounted) {
        setState(() {
          _whatWasaDoes = items;
          _barangays = barangays;
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
      appBar: AppBar(title: const Text('About WASA')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : ListView(
                  padding: PortalDensity.of(context).pagePadding,
                  children: [
                    PortalSection(
                      title: 'What WASA does',
                      subtitle: 'Why the association exists, in its own words',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final item in _whatWasaDoes) _bulletPoint(item.body),
                        ],
                      ),
                    ),
                    SizedBox(height: PortalSection.gapAfter(context)),
                    PortalSection(
                      title: 'Coverage area',
                      subtitle: 'GENTRI WASA covers all barangays of General Trias, Cavite',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _barangays.map((b) => Chip(label: Text(b, style: const TextStyle(fontSize: 12)))).toList(),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _bulletPoint(String text) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 10),
            child: Icon(Icons.check_circle, size: 18, color: StatusTint.onTint(context, AppColors.cleared)),
          ),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5))),
        ],
      ),
    );
  }
}
