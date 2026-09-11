import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/bulletin_comment.dart';
import '../models/membership.dart';
import '../providers/app_state.dart';
import '../services/comment_service.dart';
import '../services/supabase_service.dart';
import 'confirm_dialog.dart';

/// Whether the viewer may delete a comment: its author, or a WASA admin.
/// Mirrors the bulletin_comments_self_or_admin_delete RLS policy, which is
/// the real rule -- this only decides whether the button shows.
bool canDeleteComment({required String authorId, required String? viewerId, required bool viewerIsAdmin}) =>
    viewerId != null && (viewerIsAdmin || viewerId == authorId);

/// The comment thread under one bulletin: list, add, delete. Shared by the
/// website's News page and every app Board (bulletin_feed.dart), so the two
/// can't drift apart. Colours come from the surrounding theme.
class BulletinComments extends ConsumerStatefulWidget {
  const BulletinComments({
    super.key,
    required this.bulletinId,
    this.onLoginRequested,
    this.onCountChanged,
    this.background,
  });

  final String bulletinId;

  /// Called when a signed-out visitor tries to comment.
  final VoidCallback? onLoginRequested;

  /// Reports the number of comments after each load, for a count badge.
  final ValueChanged<int>? onCountChanged;

  final Color? background;

  @override
  ConsumerState<BulletinComments> createState() => _BulletinCommentsState();
}

class _BulletinCommentsState extends ConsumerState<BulletinComments> {
  final _service = CommentService(SupabaseService.instance);
  final _controller = TextEditingController();
  List<BulletinComment> _comments = [];
  bool _loading = true;
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final comments = await _service.fetchComments(widget.bulletinId);
      if (!mounted) return;
      setState(() {
        _comments = comments;
        _loading = false;
      });
      widget.onCountChanged?.call(comments.length);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load comments: $e')));
    }
  }

  Future<void> _submit() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      widget.onLoginRequested?.call();
      return;
    }
    final body = _controller.text.trim();
    if (body.isEmpty || _posting) return;
    setState(() => _posting = true);
    try {
      await _service.addComment(bulletinId: widget.bulletinId, profileId: userId, body: body);
      _controller.clear();
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not post comment: $e')));
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _delete(BulletinComment comment) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete comment?',
      message: 'This removes it for everyone.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (!confirmed) return;
    try {
      await _service.deleteComment(comment.id);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not delete the comment: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(authStateProvider); // show the input once someone signs in
    final viewerId = Supabase.instance.client.auth.currentUser?.id;
    final viewerIsAdmin = ref.watch(currentMembershipProvider).value?.role == AppRole.wasaAdmin;
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: widget.background ?? scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else if (_comments.isEmpty)
            Text('No comments yet -- be the first.', style: TextStyle(color: muted, fontSize: 13))
          else
            for (final c in _comments)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(c.authorName, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: scheme.onSurface)),
                              Text(DateFormat('MMM d, h:mm a').format(c.createdAt), style: TextStyle(color: muted, fontSize: 11)),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(c.body, style: TextStyle(fontSize: 13, height: 1.3, color: scheme.onSurface)),
                        ],
                      ),
                    ),
                    if (canDeleteComment(authorId: c.profileId, viewerId: viewerId, viewerIsAdmin: viewerIsAdmin))
                      IconButton(
                        icon: Icon(Icons.delete_outline, size: 18, color: scheme.error),
                        tooltip: 'Delete comment',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _delete(c),
                      ),
                  ],
                ),
              ),
          const SizedBox(height: 8),
          if (viewerId != null)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    maxLength: 1000,
                    decoration: const InputDecoration(
                      hintText: 'Write a comment...',
                      isDense: true,
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.send, color: scheme.primary),
                  tooltip: 'Post comment',
                  onPressed: _posting ? null : _submit,
                ),
              ],
            )
          else
            TextButton(
              onPressed: widget.onLoginRequested,
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              child: const Text('Log in to comment'),
            ),
        ],
      ),
    );
  }
}
