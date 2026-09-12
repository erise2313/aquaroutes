import 'package:flutter/material.dart';

import '../../../constants/app_colors.dart';
import '../../../models/web_content.dart';
import '../../../services/permit_service.dart';
import '../../../services/supabase_service.dart';
import '../../../services/web_content_service.dart';
import '../../../widgets/error_state.dart';
import '../../../widgets/portal/portal.dart';
import '../../../utils/error_text.dart';

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
      if (mounted) setState(() { _error = 'Could not load this page. ${describeError(e)}'; _isLoading = false; });
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
              : _steps.isEmpty && _permitLabels.isEmpty
              ? const PortalEmptyState(
                  icon: Icons.verified_outlined,
                  title: 'Nothing published yet',
                  message: 'The association has not published the accreditation steps yet. Check back soon.',
                )
              : ListView(
                  padding: PortalDensity.of(context).pagePadding,
                  children: [
                    if (_steps.isNotEmpty) ...[
                      PortalSection(
                        title: 'How it works',
                        subtitle: 'Every accredited station goes through the same review',
                        child: Column(
                          children: [
                            for (var i = 0; i < _steps.length; i++) _stepTile(i + 1, _steps[i].title, _steps[i].body),
                          ],
                        ),
                      ),
                      SizedBox(height: PortalSection.gapAfter(context)),
                    ],
                    PortalSection(
                      title: 'Required documents',
                      subtitle: 'The same checklist the Permit Vault asks a station for',
                      child: Column(
                        children: [
                          for (final p in _permitLabels) _permitTile(p),
                        ],
                      ),
                    ),
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

  Widget _permitTile(PermitTypeLabel permit) {
    final theme = Theme.of(context);

    return PortalCard(
      lift: false,
      accent: AppColors.seal,
      margin: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.description_outlined, color: StatusTint.onTint(context, AppColors.seal)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(permit.label, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  permit.conditionNote,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
