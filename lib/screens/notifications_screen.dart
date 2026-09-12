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
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

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
      AppRole.stationOwner => const MerchantOrdersScreen(),
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        data: (notifications) {
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
              return ListTile(
                leading: Icon(
                  switch (notification.category) {
                    'permit' => Icons.folder_shared_outlined,
                    'accreditation' => Icons.verified_outlined,
                    'account' => Icons.manage_accounts_outlined,
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
                trailing: notification.isRead
                    ? null
                    : Icon(Icons.circle, size: 10, color: Theme.of(context).colorScheme.primary),
                onTap: () {
                  if (!notification.isRead) service.markRead(notification.id);
                  if (destination != null) {
                    Navigator.push(context, appRoute(destination));
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}
