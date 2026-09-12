import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../providers/app_state.dart';
import '../../widgets/portal/portal.dart';
import '../auth/login_screen.dart';
import 'my_orders_screen.dart';
import 'track_order_screen.dart';
import '../app_route.dart';

/// Front door for order tracking from the main bottom nav -- previously
/// both MyOrdersScreen (logged-in) and TrackOrderScreen (guest) existed but
/// were only reachable by digging into the Account menu, so this tab makes
/// tracking a delivery a one-tap action regardless of login state.
class OrdersTabScreen extends ConsumerWidget {
  const OrdersTabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(authStateProvider); // rebuild when the user logs in/out
    final isLoggedIn = Supabase.instance.client.auth.currentUser != null;

    // No app bar on either branch: PublicHomeScreen's shell already supplies
    // one, and rendering a second stacked two bars in this tab.
    if (isLoggedIn) {
      return const MyOrdersScreen(showAppBar: false);
    }

    return Scaffold(
      body: PortalEmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'Track a delivery',
        message: 'Look up a guest order with its ID and phone number, or sign in to see your full order history.',
        action: PortalActionRow(
          children: [
            FilledButton.icon(
              onPressed: () => Navigator.push(context, appRoute(const TrackOrderScreen())),
              icon: const Icon(Icons.search),
              label: const Text('Track a guest order'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.push(context, appRoute(const LoginScreen())),
              child: const Text('Sign in'),
            ),
          ],
        ),
      ),
    );
  }
}
