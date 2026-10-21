import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_notification.dart';
import '../models/membership.dart';
import '../providers/app_state.dart';
import 'app_route.dart';
import 'merchant/orders_screen.dart';
import 'merchant/permit_vault_screen.dart';
import 'public/my_orders_screen.dart';
import '../utils/error_text.dart';

/// The in-app inbox, shared by every portal (the bell in each app bar opens
/// it). Rows come from database triggers via Realtime, so this screen only
/// displays them and marks them read.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  /// Deleted here, hidden at once: a swiped-away row must leave the list in
  /// the same frame, before the live stream reports the delete.
  final _removed = <String>{};

  /// Where a notification leads, which depends on who is reading it: a
  /// customer's orders live in My Orders, an owner's in the station's
  /// Orders screen, and permit news in the Permit Vault.
  Widget? _destinationFor(AppNotification notification, AppRole? role) {
    if (notification.category == 'permit' || notification.category == 'accreditation') {
      return role == AppRole.stationOwner ? const PermitVaultScreen() : null;
    }
    if (notification.orderId == null) return null;
    return switch (role) {
      AppRole.publicConsumer => const MyOrdersScreen(),
      AppRole.stationOwner || AppRole.stationStaff => const MerchantOrdersScreen(),
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final notificationsAsync = ref.watch(notificationsProvider);
    final role = ref.watch(currentMembershipProvider).value?.role;
    final service = ref.watch(notificationServiceProvider);
    final unread = ref.watch(unreadNotificationCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (unread > 0)
            TextButton(
              onPressed: service.markAllRead,
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: notificationsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not load your notifications. ${describeError(e)}', textAlign: TextAlign.center),
          ),
        ),
        data: (all) {
          final notifications = [for (final n in all) if (!_removed.contains(n.id)) n];
          if (notifications.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.notifications_none_outlined, size: 56, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(height: 12),
                    const Text('Nothing yet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(
                      'Order updates and WASA decisions show up here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            itemCount: notifications.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final notification = notifications[index];
              final destination = _destinationFor(notification, role);
              Future<void> remove() async {
                setState(() => _removed.add(notification.id));
                try {
                  await service.delete(notification.id);
                } catch (e) {
                  if (mounted) setState(() => _removed.remove(notification.id));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not delete. ${describeError(e)}')));
                  }
                }
              }

              // Swipe either way, or the bin button, removes it.
              return Dismissible(
                key: ValueKey(notification.id),
                onDismissed: (_) => remove(),
                background: Container(
                  color: Theme.of(context).colorScheme.errorContainer,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.onErrorContainer),
                ),
                secondaryBackground: Container(
                  color: Theme.of(context).colorScheme.errorContainer,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.onErrorContainer),
                ),
                child: ListTile(
                leading: Icon(
                  switch (notification.category) {
                    'permit' => Icons.folder_shared_outlined,
                    'accreditation' => Icons.verified_outlined,
                    'account' => Icons.manage_accounts_outlined,
                    'worker' => Icons.gavel_outlined,
                    'bulletin' => Icons.campaign_outlined,
                    _ => Icons.local_shipping_outlined,
                  },
                  color: notification.isRead ? Theme.of(context).colorScheme.onSurfaceVariant : Theme.of(context).colorScheme.primary,
                ),
                title: Text(
                  notification.title,
                  style: TextStyle(fontWeight: notification.isRead ? FontWeight.w500 : FontWeight.bold),
                ),
                subtitle: Text(
                  notification.body == null
                      ? notificationAge(notification.createdAt)
                      : '${notification.body}\n${notificationAge(notification.createdAt)}',
                ),
                isThreeLine: notification.body != null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!notification.isRead)
                      Icon(Icons.circle, size: 10, color: Theme.of(context).colorScheme.primary, semanticLabel: 'Unread'),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Delete notification',
                      onPressed: remove,
                    ),
                  ],
                ),
                onTap: () {
                  if (!notification.isRead) service.markRead(notification.id);
                  if (destination != null) {
                    Navigator.push(context, appRoute(destination));
                  }
                },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
