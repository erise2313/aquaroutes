import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/app_colors.dart';
import '../../models/resource.dart';
import '../../providers/web_locale_provider.dart';
import '../../services/resource_service.dart';
import '../../services/supabase_service.dart';
import '../../web_strings.dart';
import '../../widgets/back_to_top_button.dart';
import '../../widgets/error_state.dart';
import '../../widgets/fade_slide_in.dart';
import '../../widgets/hover_scale.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/web_footer.dart';
import '../../widgets/web_nav_bar.dart';

/// Public downloadable resources -- reuses ResourceService.fetchResources(),
/// the same query backing resources_admin_screen.dart's upload/manage view.
/// Downloads go through url_launcher (already a dependency, same as the
/// Contact page's mailto link) rather than any bespoke download machinery.
class ResourcesScreen extends ConsumerStatefulWidget {
  const ResourcesScreen({super.key});

  @override
  ConsumerState<ResourcesScreen> createState() => _ResourcesScreenState();
}

class _ResourcesScreenState extends ConsumerState<ResourcesScreen> {
  final _resourceService = ResourceService(SupabaseService.instance);
  final _scrollController = ScrollController();

  bool _isLoading = true;
  String? _error;
  List<Resource> _resources = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final resources = await _resourceService.fetchResources();
      if (mounted) setState(() { _resources = resources; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Could not load resources: $e'; _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(webLocaleProvider);
    String t(String key) => WebStrings.t(locale, key);

    return Scaffold(
      appBar: const WebNavBar(currentPage: WebPage.resources),
      body: Stack(
        children: [
          SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FadeSlideIn(
                            child: Text(t('resources_title'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(height: 12),
                          FadeSlideIn(
                            delay: const Duration(milliseconds: 80),
                            child: Text(t('resources_intro'), style: const TextStyle(fontSize: 16, height: 1.5)),
                          ),
                          const SizedBox(height: 24),
                          if (_isLoading)
                            const SkeletonList(count: 3, cardHeight: 72)
                          else if (_error != null)
                            ErrorState(message: _error!, onRetry: _load)
                          else if (_resources.isEmpty)
                            const Text('No resources available yet.', style: TextStyle(color: Colors.grey))
                          else
                            for (var i = 0; i < _resources.length; i++)
                              FadeSlideIn(delay: Duration(milliseconds: 140 + i * 50), child: _buildResourceCard(_resources[i])),
                        ],
                      ),
                    ),
                  ),
                ),
                const WebFooter(),
              ],
            ),
          ),
          BackToTopButton(controller: _scrollController),
        ],
      ),
    );
  }

  Widget _buildResourceCard(Resource resource) {
    return HoverScale(
      scale: 1.01,
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          leading: const Icon(Icons.picture_as_pdf_outlined, color: Colors.red, size: 32),
          title: Text(resource.title, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('${resource.category} · Added ${DateFormat('MMM d, yyyy').format(resource.createdAt)}'),
          trailing: const Icon(Icons.download, color: AppColors.primary),
          onTap: () => launchUrl(Uri.parse(resource.fileUrl)),
        ),
      ),
    );
  }
}
