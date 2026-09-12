import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_notification.dart';
import '../providers/app_state.dart';
import '../screens/app_route.dart';
import '../screens/notifications_screen.dart';

/// Bell with an unread count, for every signed-in surface's app bar.
///
/// It also announces notifications that arrive while the app is open: the
/// inbox is fed by Realtime (providers/app_state.dart), so a new row shows
/// up here without any polling. Phone push, when the association's app ID
/// is settled, will read the same rows.
class NotificationBell extends ConsumerStatefulWidget {
  const NotificationBell({super.key});

  @override
  ConsumerState<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends ConsumerState<NotificationBell> {
  String? _lastSeenId;

  void _open() {
    Navigator.push(context, ambientRoute(context, const NotificationsScreen()));
  }

  void _announce(List<AppNotification> notifications) {
    if (notifications.isEmpty) return;
    final newest = notifications.first;
    // First load just records where we are -- otherwise every sign-in would
    // pop a banner for something the person has already seen.
    if (_lastSeenId == null) {
      _lastSeenId = newest.id;
      return;
    }
    if (newest.id == _lastSeenId || newest.isRead) return;
    _lastSeenId = newest.id;

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(SnackBar(
      content: Text(newest.body == null ? newest.title : '${newest.title} · ${newest.body}'),
      duration: const Duration(seconds: 5),
      action: SnackBarAction(label: 'View', onPressed: _open),
    ));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<AppNotification>>>(notificationsProvider, (_, next) {
      final notifications = next.value;
      if (notifications != null) _announce(notifications);
    });

    final unread = ref.watch(unreadNotificationCountProvider);
    final icon = Icon(unread > 0 ? Icons.notifications_active : Icons.notifications_none_outlined);

    return IconButton(
      tooltip: unread > 0 ? '$unread unread notifications' : 'Notifications',
      onPressed: _open,
      icon: unread > 0 ? Badge.count(count: unread, child: icon) : icon,
    );
  }
}
