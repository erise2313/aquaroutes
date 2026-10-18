import 'package:flutter/material.dart';

import '../../../models/web_content.dart';
import '../../../utils/error_text.dart';
import '../../../widgets/error_state.dart';
import '../../../widgets/portal/portal.dart';
import '../../web/safe_water_screen.dart' show fetchSafeWaterArticles, safeWaterIcons;

/// In-app mirror of the website's safe-water page -- the same
/// admin-editable articles (web_content_items page 'safe_water').
class SafeWaterInfoScreen extends StatefulWidget {
  const SafeWaterInfoScreen({super.key});

  @override
  State<SafeWaterInfoScreen> createState() => _SafeWaterInfoScreenState();
}

class _SafeWaterInfoScreenState extends State<SafeWaterInfoScreen> {
  bool _isLoading = true;
  String? _error;
  List<WebContentItem> _articles = [];

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
      final articles = await fetchSafeWaterArticles();
      if (mounted) {
        setState(() {
          _articles = articles;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load this page. ${describeError(e)}';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Safe drinking water')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : _articles.isEmpty
                  ? const PortalEmptyState(
                      icon: Icons.water_drop_outlined,
                      title: 'Nothing here yet',
                      message: 'The association hasn\'t published its safe-water advice yet.',
                    )
                  : ListView(
                      padding: PortalDensity.of(context).pagePadding,
                      children: [
                        for (final a in _articles)
                          PortalCard(
                            lift: false,
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(safeWaterIcons[a.icon] ?? Icons.water_drop_outlined, color: theme.colorScheme.primary, size: 28),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(a.title, style: theme.textTheme.titleMedium),
                                      const SizedBox(height: 6),
                                      Text(a.body, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
    );
  }
}
