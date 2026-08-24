import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/web_theme.dart';
import '../../models/bulletin.dart';
import '../../models/bulletin_comment.dart';
import '../../providers/app_state.dart';
import '../../providers/web_locale_provider.dart';
import '../../services/bulletin_service.dart';
import '../../services/comment_service.dart';
import '../../services/supabase_service.dart';
import '../../web_strings.dart';
import '../../widgets/back_to_top_button.dart';
import '../../widgets/error_state.dart';
import '../../widgets/fade_slide_in.dart';
import '../../widgets/hover_scale.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/web_footer.dart';
import '../../widgets/web_nav_bar.dart';
import '../../widgets/web_page_header.dart';
import '../../widgets/web_page_route.dart';
import '../auth/login_screen.dart';

/// Full news history for the website -- reuses BulletinService.fetchBulletins()
/// (the same query backing bulletin_feed.dart's mobile board) rather than a
/// separate query, with category filtering, the pinned post promoted to a
/// featured card, and (new this pass) reactions + comments -- the backend
/// for reactions already existed and was simply never surfaced here; comments
/// are a genuinely new table (bulletin_comments).
class NewsScreen extends ConsumerStatefulWidget {
  const NewsScreen({super.key});

  @override
  ConsumerState<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends ConsumerState<NewsScreen> {
  final _bulletinService = BulletinService(SupabaseService.instance);
  final _commentService = CommentService(SupabaseService.instance);

  bool _isLoading = true;
  String? _error;
  List<Bulletin> _bulletins = [];
  BulletinCategory? _filter;
  final _scrollController = ScrollController();

  Map<String, int> _reactionCounts = {};
  Set<String> _myReactions = {};

  final Map<String, List<BulletinComment>> _comments = {};
  final Set<String> _expandedComments = {};
  final Set<String> _loadingComments = {};
  final Map<String, TextEditingController> _commentControllers = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    for (final c in _commentControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final bulletins = await _bulletinService.fetchBulletins();
      final counts = await _bulletinService.fetchReactionCounts();
      final userId = Supabase.instance.client.auth.currentUser?.id;
      final mine = userId != null ? await _bulletinService.fetchMyReactions(userId) : <String>{};
      if (mounted) {
        setState(() {
          _bulletins = bulletins;
          _reactionCounts = counts;
          _myReactions = mine;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load news: $e';
          _isLoading = false;
        });
      }
    }
  }

  List<Bulletin> get _filtered {
    if (_filter == null) return _bulletins;
    return _bulletins.where((b) => b.category == _filter).toList();
  }

  Future<void> _toggleReaction(String bulletinId) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      _promptLogin('react to a post');
      return;
    }
    final wasReacted = _myReactions.contains(bulletinId);
    setState(() {
      if (wasReacted) {
        _myReactions.remove(bulletinId);
        _reactionCounts[bulletinId] = (_reactionCounts[bulletinId] ?? 1) - 1;
      } else {
        _myReactions.add(bulletinId);
        _reactionCounts[bulletinId] = (_reactionCounts[bulletinId] ?? 0) + 1;
      }
    });
    try {
      if (wasReacted) {
        await _bulletinService.removeReaction(bulletinId, userId);
      } else {
        await _bulletinService.addReaction(bulletinId, userId);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update reaction: $e')));
      await _load();
    }
  }

  void _promptLogin(String action) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Log in to $action.'),
        action: SnackBarAction(label: 'Log In', onPressed: () => Navigator.push(context, webPageRoute(const LoginScreen()))),
      ),
    );
  }

  Future<void> _toggleComments(String bulletinId) async {
    if (_expandedComments.contains(bulletinId)) {
      setState(() => _expandedComments.remove(bulletinId));
      return;
    }
    setState(() {
      _expandedComments.add(bulletinId);
      _loadingComments.add(bulletinId);
    });
    try {
      final comments = await _commentService.fetchComments(bulletinId);
      if (mounted) {
        setState(() {
          _comments[bulletinId] = comments;
          _loadingComments.remove(bulletinId);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingComments.remove(bulletinId));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load comments: $e')));
      }
    }
  }

  Future<void> _submitComment(String bulletinId) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      _promptLogin('leave a comment');
      return;
    }
    final controller = _commentControllers[bulletinId];
    final body = controller?.text.trim() ?? '';
    if (body.isEmpty) return;

    try {
      await _commentService.addComment(bulletinId: bulletinId, profileId: userId, body: body);
      controller?.clear();
      final comments = await _commentService.fetchComments(bulletinId);
      if (mounted) setState(() => _comments[bulletinId] = comments);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not post comment: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(authStateProvider); // rebuild on login/logout so react/comment gating stays correct
    final locale = ref.watch(webLocaleProvider);
    String t(String key) => WebStrings.t(locale, key);
    final filtered = _filtered;
    final featured = _filter == null ? _bulletins.where((b) => b.isPinned).toList() : <Bulletin>[];
    final rest = filtered.where((b) => !featured.contains(b)).toList();

    return Scaffold(
      backgroundColor: WebTheme.paper,
      appBar: const WebNavBar(currentPage: WebPage.news),
      body: Stack(
        children: [
          _isLoading
              ? SingleChildScrollView(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            SkeletonBlock(width: 180, height: 28),
                            SizedBox(height: 24),
                            SkeletonList(count: 4, cardHeight: 100),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : SingleChildScrollView(
              controller: _scrollController,
              child: Column(
                children: [
                  FadeSlideIn(child: WebPageHeader(eyebrow: 'ASSOCIATION NEWS', title: t('news_title'))),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _filterChip('All', null),
                                  const SizedBox(width: 8),
                                  _filterChip('Announcements', BulletinCategory.announcement),
                                  const SizedBox(width: 8),
                                  _filterChip('Price Changes', BulletinCategory.priceChange),
                                  const SizedBox(width: 8),
                                  _filterChip('Events', BulletinCategory.event),
                                  const SizedBox(width: 8),
                                  _filterChip('Discussion', BulletinCategory.discussion),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            for (final b in featured) _buildFeaturedCard(b),
                            if (featured.isNotEmpty) const SizedBox(height: 8),
                            if (filtered.isEmpty) const Text('No posts yet.', style: TextStyle(color: Colors.grey)),
                            for (final b in rest) _buildCard(b),
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

  Widget _filterChip(String label, BulletinCategory? category) {
    final selected = _filter == category;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _filter = category),
      selectedColor: WebTheme.harborBlue,
      labelStyle: TextStyle(color: selected ? Colors.white : WebTheme.inkNavy),
      backgroundColor: WebTheme.foam,
      side: BorderSide.none,
    );
  }

  Widget _buildFeaturedCard(Bulletin bulletin) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(color: WebTheme.sealGold.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: WebTheme.sealGold.withValues(alpha: 0.35))),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [Icon(Icons.push_pin, size: 16, color: WebTheme.sealGold), SizedBox(width: 6), Text('Pinned', style: TextStyle(color: WebTheme.sealGold, fontWeight: FontWeight.bold, fontSize: 12))]),
            const SizedBox(height: 10),
            Text(bulletin.title, style: WebTheme.display(fontSize: 22)),
            const SizedBox(height: 10),
            Text(bulletin.body, style: const TextStyle(fontSize: 15, height: 1.5, color: WebTheme.inkNavy)),
            if (bulletin.imageUrl != null) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  bulletin.imageUrl!,
                  height: 240,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 240,
                    width: double.infinity,
                    color: Colors.grey.shade200,
                    child: const Icon(Icons.image_not_supported_outlined, color: Colors.grey, size: 32),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text('${bulletin.authorBadge} · ${DateFormat('MMM d, yyyy').format(bulletin.createdAt)}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 12),
            _buildInteractionBar(bulletin),
            if (_expandedComments.contains(bulletin.id)) _buildCommentsSection(bulletin.id),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(Bulletin bulletin) {
    final (categoryColor, categoryLabel) = switch (bulletin.category) {
      BulletinCategory.announcement => (WebTheme.harborBlue, 'Announcement'),
      BulletinCategory.priceChange => (const Color(0xFF0B8A7A), 'Price Change'),
      BulletinCategory.event => (const Color(0xFFC96A2E), 'Event'),
      BulletinCategory.discussion => (Colors.blueGrey, 'Discussion'),
    };

    return HoverScale(
      scale: 1.005,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(color: WebTheme.foam, borderRadius: BorderRadius.circular(10)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: categoryColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                child: Text(categoryLabel, style: TextStyle(color: categoryColor, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 10),
              Text(bulletin.title, style: WebTheme.display(fontSize: 18)),
              const SizedBox(height: 6),
              Text(bulletin.body, style: const TextStyle(color: Colors.black87, height: 1.4)),
              if (bulletin.imageUrl != null) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    bulletin.imageUrl!,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      height: 200,
                      width: double.infinity,
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.image_not_supported_outlined, color: Colors.grey, size: 32),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text('${bulletin.authorBadge} · ${DateFormat('MMM d, yyyy').format(bulletin.createdAt)}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 10),
              _buildInteractionBar(bulletin),
              if (_expandedComments.contains(bulletin.id)) _buildCommentsSection(bulletin.id),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInteractionBar(Bulletin bulletin) {
    final reacted = _myReactions.contains(bulletin.id);
    final count = _reactionCounts[bulletin.id] ?? 0;
    final commentCount = _comments[bulletin.id]?.length;

    return Row(
      children: [
        InkWell(
          onTap: () => _toggleReaction(bulletin.id),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(reacted ? Icons.favorite : Icons.favorite_border, size: 18, color: reacted ? Colors.redAccent : Colors.grey.shade600),
                const SizedBox(width: 6),
                Text('$count', style: TextStyle(color: reacted ? Colors.redAccent : Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 20),
        InkWell(
          onTap: () => _toggleComments(bulletin.id),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.mode_comment_outlined, size: 17, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Text(commentCount != null ? '$commentCount' : 'Comments', style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCommentsSection(String bulletinId) {
    final comments = _comments[bulletinId] ?? [];
    final isLoading = _loadingComments.contains(bulletinId);
    final controller = _commentControllers.putIfAbsent(bulletinId, () => TextEditingController());
    final isLoggedIn = Supabase.instance.client.auth.currentUser != null;

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isLoading)
              const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))))
            else if (comments.isEmpty)
              const Text('No comments yet -- be the first.', style: TextStyle(color: Colors.grey, fontSize: 13))
            else
              for (final c in comments)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(c.authorName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: WebTheme.inkNavy)),
                          const SizedBox(width: 8),
                          Text(DateFormat('MMM d, h:mm a').format(c.createdAt), style: const TextStyle(color: Colors.grey, fontSize: 11)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(c.body, style: const TextStyle(fontSize: 13, height: 1.3)),
                    ],
                  ),
                ),
            const SizedBox(height: 8),
            if (isLoggedIn)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      decoration: const InputDecoration(hintText: 'Write a comment...', isDense: true, border: OutlineInputBorder()),
                      onSubmitted: (_) => _submitComment(bulletinId),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(icon: const Icon(Icons.send, color: WebTheme.harborBlue), onPressed: () => _submitComment(bulletinId)),
                ],
              )
            else
              TextButton(
                onPressed: () => _promptLogin('leave a comment'),
                style: TextButton.styleFrom(foregroundColor: WebTheme.harborBlue, padding: EdgeInsets.zero),
                child: const Text('Log in to comment'),
              ),
          ],
        ),
      ),
    );
  }
}
