import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/bulletin.dart';
import '../../models/membership.dart';
import '../../models/order.dart';
import '../../models/product.dart';
import '../../providers/app_state.dart';
import '../../services/bulletin_service.dart';
import '../../services/photo_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/formatters.dart';
import '../../constants/app_colors.dart';
import '../../widgets/bulletin_comments.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/error_state.dart';
import '../../widgets/portal/portal.dart';
import '../auth/login_screen.dart';
import '../auth/registration_screen.dart';
import '../app_route.dart';
import '../../utils/error_text.dart';

/// Reusable feed body (not a full Scaffold) shared by the guest home
/// (screens/public/public_home_screen.dart) and the authenticated
/// bulletin board entry points reachable from each portal
/// (screens/public/bulletin_board_screen.dart). Derives the current
/// role/station from Riverpod (currentMembershipProvider/
/// currentStationProvider, providers/app_state.dart) rather than taking it
/// as a parameter, so a guest session (no membership row) naturally gets
/// the login-gated FAB with no extra plumbing.
class BulletinFeed extends ConsumerStatefulWidget {
  const BulletinFeed({super.key});

  @override
  ConsumerState<BulletinFeed> createState() => _BulletinFeedState();
}

class _BulletinFeedState extends ConsumerState<BulletinFeed> {
  final _bulletinService = BulletinService(SupabaseService.instance);
  final _photoService = PhotoService(SupabaseService.instance);

  bool _isLoading = true;
  String? _error;
  List<Bulletin> _bulletins = [];
  List<FloorPrice> _floorPrices = [];
  Map<String, int> _reactionCounts = {};
  Set<String> _myReactions = {};
  final Set<String> _pendingReactionToggles = {};
  BulletinCategory? _filter;
  final Set<String> _expandedComments = {};
  final Map<String, int> _commentCounts = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final bulletins = await _bulletinService.fetchBulletins();
      final floorPrices = await _bulletinService.fetchFloorPrices();
      final reactionCounts = await _bulletinService.fetchReactionCounts();
      final userId = Supabase.instance.client.auth.currentUser?.id;
      final myReactions = userId == null ? <String>{} : await _bulletinService.fetchMyReactions(userId);
      if (mounted) {
        setState(() {
          _bulletins = bulletins;
          _floorPrices = floorPrices;
          _reactionCounts = reactionCounts;
          _myReactions = myReactions;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load the bulletin board. ${describeError(e)}';
          _isLoading = false;
        });
      }
    }
  }

  List<Bulletin> get _filteredBulletins {
    if (_filter == null) return _bulletins;
    return _bulletins.where((b) => b.category == _filter).toList();
  }

  void _showLoginPrompt() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Login Required'),
        content: const Text('Log in or register to post on the Association Bulletin Board.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(context, ambientRoute(context, const RegistrationScreen()));
            },
            child: const Text('Register'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(context, ambientRoute(context, const LoginScreen()));
            },
            child: const Text('Login'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleNewPostTap(Membership? membership) async {
    if (membership == null) {
      _showLoginPrompt();
      return;
    }

    final allowedCategories = _bulletinService.allowedCategoriesFor(membership.role);
    if (allowedCategories.isEmpty) {
      _showLoginPrompt();
      return;
    }

    String authorName = 'GENTRI WASA Member';
    String? stationName;
    try {
      final supabase = Supabase.instance.client;
      final profile = await supabase.from('profiles').select('full_name').eq('id', membership.profileId).maybeSingle();
      authorName = profile?['full_name'] as String? ?? authorName;

      if (membership.stationId != null) {
        final station = await supabase.from('water_stations').select('station_name').eq('id', membership.stationId!).maybeSingle();
        stationName = station?['station_name'] as String?;
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open the post form. ${describeError(e)}')));
      return;
    }

    if (!mounted) return;
    _showCreatePostSheet(
      membership: membership,
      allowedCategories: allowedCategories,
      authorName: authorName,
      stationName: stationName,
    );
  }

  void _showCreatePostSheet({
    required Membership membership,
    required List<BulletinCategory> allowedCategories,
    required String authorName,
    String? stationName,
  }) {
    BulletinCategory selectedCategory = allowedCategories.first;
    final titleController = TextEditingController();
    final bodyController = TextEditingController();
    bool isSubmitting = false;
    Uint8List? selectedImageBytes;
    String? selectedImageExtension;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('New Post', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              DropdownButtonFormField<BulletinCategory>(
                initialValue: selectedCategory,
                decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                items: allowedCategories
                    .map((c) => DropdownMenuItem(value: c, child: Text(bulletinCategoryLabel(c))))
                    .toList(),
                onChanged: (val) => setSheetState(() => selectedCategory = val ?? selectedCategory),
              ),
              const SizedBox(height: 12),
              TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(
                controller: bodyController,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Body', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              if (selectedImageBytes != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(selectedImageBytes!, height: 140, width: double.infinity, fit: BoxFit.cover),
                ),
                const SizedBox(height: 8),
              ],
              OutlinedButton.icon(
                onPressed: () async {
                  final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
                  final picked = result?.files.single;
                  if (picked != null && picked.bytes != null) {
                    setSheetState(() {
                      selectedImageBytes = picked.bytes;
                      selectedImageExtension = picked.extension ?? 'jpg';
                    });
                  }
                },
                icon: const Icon(Icons.add_a_photo_outlined),
                label: Text(selectedImageBytes == null ? 'Attach Photo (optional)' : 'Change Photo'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: isSubmitting
                    ? null
                    : () async {
                        if (titleController.text.trim().isEmpty || bodyController.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Title and body are both required.')),
                          );
                          return;
                        }
                        setSheetState(() => isSubmitting = true);

                        // Tracked so a post-creation failure after a
                        // successful upload can clean the file back up --
                        // otherwise it's an orphaned file nothing ever
                        // references, and a retry would upload yet another.
                        String? uploadedImagePath;
                        try {
                          // Uploaded to a self-contained path BEFORE the post
                          // is created (see PhotoService.uploadBulletinImage)
                          // since non-admin posters only have an INSERT
                          // policy on bulletins, not UPDATE.
                          String? imageUrl;
                          if (selectedImageBytes != null) {
                            final uploaded = await _photoService.uploadBulletinImage(
                              authorProfileId: membership.profileId,
                              bytes: selectedImageBytes!,
                              fileExtension: selectedImageExtension ?? 'jpg',
                            );
                            uploadedImagePath = uploaded.path;
                            imageUrl = uploaded.publicUrl;
                          }

                          final associationId = await _bulletinService.fetchDefaultAssociationId();
                          await _bulletinService.postBulletin(
                            associationId: associationId,
                            category: selectedCategory,
                            title: titleController.text.trim(),
                            body: bodyController.text.trim(),
                            postedByProfileId: membership.profileId,
                            authorName: authorName,
                            authorRole: membership.role,
                            authorStationName: stationName,
                            imageUrl: imageUrl,
                          );
                          if (context.mounted) Navigator.pop(context);
                          _load();
                        } catch (e) {
                          if (uploadedImagePath != null) {
                            // Best-effort cleanup -- don't let a cleanup
                            // failure mask the original error from the user.
                            unawaited(_photoService.deleteBulletinImage(uploadedImagePath).catchError((_) {}));
                          }
                          setSheetState(() => isSubmitting = false);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
                          }
                        }
                      },
                child: isSubmitting
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Post'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final membershipAsync = ref.watch(currentMembershipProvider);
    final membership = membershipAsync.value;

    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? ErrorState(message: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: PortalDensity.of(context).pagePadding,
                children: [
                  if (_floorPrices.isNotEmpty) ...[
                    PortalSection(
                      title: 'Official floor prices',
                      subtitle: 'The least a member station may charge for a refill',
                      child: Column(
                        children: [
                          for (var i = 0; i < _floorPrices.length; i++)
                            _buildFloorPriceCard(_floorPrices[i], last: i == _floorPrices.length - 1),
                        ],
                      ),
                    ),
                    SizedBox(height: PortalSection.gapAfter(context)),
                  ],
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('All Posts', null),
                        const SizedBox(width: 8),
                        _buildFilterChip('Official Announcements', BulletinCategory.announcement),
                        const SizedBox(width: 8),
                        _buildFilterChip('Price Changes', BulletinCategory.priceChange),
                        const SizedBox(width: 8),
                        _buildFilterChip('Community Events', BulletinCategory.event),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_filteredBulletins.isEmpty)
                    PortalEmptyState(
                      icon: Icons.campaign_outlined,
                      title: _filter == null ? 'No posts yet' : 'Nothing in this category',
                      message: _filter == null
                          ? 'Announcements, price changes and events from the association appear here.'
                          : 'Try another category, or show all posts.',
                      action: _filter == null
                          ? null
                          : TextButton.icon(
                              onPressed: () => setState(() => _filter = null),
                              icon: const Icon(Icons.clear),
                              label: const Text('Show all posts'),
                            ),
                    ),
                  ..._filteredBulletins.map((b) => _buildBulletinCard(b, membership)),
                ],
              ),
            ),
      // Only offered to someone who can actually post. A signed-in customer
      // has no posting categories at all, so this used to show them a New
      // Post button whose answer was a prompt to log in -- while they were
      // already logged in. Gated on the service rather than a hardcoded role
      // list, so the button cannot drift from the permission it represents.
      // A guest (membership == null) keeps it as the login entry point, the
      // behaviour the class comment above describes.
      floatingActionButton:
          membership != null && _bulletinService.allowedCategoriesFor(membership.role).isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _handleNewPostTap(membership),
              icon: const Icon(Icons.add),
              label: const Text('New Post'),
            ),
    );
  }

  Widget _buildFloorPriceCard(FloorPrice fp, {required bool last}) {
    final theme = Theme.of(context);
    final density = PortalDensity.of(context);

    return PortalCard(
      lift: false,
      accent: AppColors.primary,
      margin: EdgeInsets.only(bottom: last ? 0 : density.gap),
      child: Row(
        children: [
          Icon(Icons.water_drop, color: StatusTint.onTint(context, AppColors.primary)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fp.containerCode == null
                      ? waterTypeLabel(fp.waterType)
                      : '${waterTypeLabel(fp.waterType)} · ${containerLabel(fp.containerCode) ?? fp.containerCode} refill',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  'Effective ${DateFormat('MMM d, yyyy').format(fp.effectiveDate)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Min ${formatPeso(fp.minPricePerJug)}',
            style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, BulletinCategory? category) {
    final selected = _filter == category;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _filter = category),
    );
  }

  Future<void> _toggleReaction(Bulletin bulletin, Membership? membership) async {
    if (membership == null) {
      _showLoginPrompt();
      return;
    }
    // Guards against a rapid double-tap firing two concurrent requests
    // whose responses could arrive out of order and leave the optimistic
    // local state out of sync with the server until the next reload.
    if (_pendingReactionToggles.contains(bulletin.id)) return;
    _pendingReactionToggles.add(bulletin.id);

    final hasReacted = _myReactions.contains(bulletin.id);
    setState(() {
      if (hasReacted) {
        _myReactions.remove(bulletin.id);
        _reactionCounts[bulletin.id] = (_reactionCounts[bulletin.id] ?? 1) - 1;
      } else {
        _myReactions.add(bulletin.id);
        _reactionCounts[bulletin.id] = (_reactionCounts[bulletin.id] ?? 0) + 1;
      }
    });
    try {
      if (hasReacted) {
        await _bulletinService.removeReaction(bulletin.id, membership.profileId);
      } else {
        await _bulletinService.addReaction(bulletin.id, membership.profileId);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
      _load();
    } finally {
      _pendingReactionToggles.remove(bulletin.id);
    }
  }

  Future<void> _togglePin(Bulletin bulletin) async {
    try {
      await _bulletinService.togglePin(bulletin.id, !bulletin.isPinned);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  Future<void> _deleteBulletin(Bulletin bulletin) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete Post?',
      message: 'This will permanently remove "${bulletin.title}" from the bulletin board.',
      confirmLabel: 'Delete',
    );
    if (!confirmed) return;

    try {
      await _bulletinService.deleteBulletin(bulletin.id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Post deleted.')));
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  Widget _buildBulletinCard(Bulletin bulletin, Membership? membership) {
    final (categoryColor, categoryLabel) = switch (bulletin.category) {
      BulletinCategory.announcement => (Colors.indigo, 'Announcement'),
      BulletinCategory.priceChange => (Colors.teal, 'Price Change'),
      BulletinCategory.event => (Colors.deepOrange, 'Event'),
      BulletinCategory.discussion => (Colors.blueGrey, 'Discussion'),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      // A pale amber wash assumed dark text; in dark mode it swallowed the
      // pinned post's title and body entirely.
      color: bulletin.isPinned ? StatusTint.surface(context, Colors.amber) : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (bulletin.isPinned) const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.push_pin, size: 16, color: Colors.amber),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: categoryColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                  child: Text(categoryLabel, style: TextStyle(color: categoryColor, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                if (membership?.role == AppRole.wasaAdmin) ...[
                  const Spacer(),
                  IconButton(
                    icon: Icon(bulletin.isPinned ? Icons.push_pin : Icons.push_pin_outlined, size: 18),
                    tooltip: bulletin.isPinned ? 'Unpin' : 'Pin',
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    onPressed: () => _togglePin(bulletin),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                    tooltip: 'Delete',
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    onPressed: () => _deleteBulletin(bulletin),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(bulletin.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 6),
            Text(bulletin.body),
            if (bulletin.imageUrl != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(bulletin.imageUrl!, height: 160, width: double.infinity, fit: BoxFit.cover),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    bulletin.authorName,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(DateFormat('MMM d, yyyy').format(bulletin.createdAt), style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
              ],
            ),
            Text(bulletin.authorBadge, style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
            const SizedBox(height: 4),
            Row(
              children: [
                InkWell(
                  onTap: () => _toggleReaction(bulletin, membership),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _myReactions.contains(bulletin.id) ? Icons.favorite : Icons.favorite_border,
                          size: 18,
                          color: _myReactions.contains(bulletin.id) ? Colors.red : Colors.grey,
                        ),
                        const SizedBox(width: 6),
                        Text('${_reactionCounts[bulletin.id] ?? 0}', style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Comments used to exist only on the website's News page.
                InkWell(
                  onTap: () => setState(() {
                    if (!_expandedComments.remove(bulletin.id)) _expandedComments.add(bulletin.id);
                  }),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.mode_comment_outlined, size: 17, color: Colors.grey.shade700),
                        const SizedBox(width: 6),
                        Text(
                          _commentCounts[bulletin.id]?.toString() ?? 'Comments',
                          style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (_expandedComments.contains(bulletin.id)) ...[
              const SizedBox(height: 8),
              BulletinComments(
                bulletinId: bulletin.id,
                onLoginRequested: _showLoginPrompt,
                onCountChanged: (count) => setState(() => _commentCounts[bulletin.id] = count),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
