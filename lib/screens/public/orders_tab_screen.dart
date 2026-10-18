import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../providers/app_state.dart';
import '../../widgets/portal/portal.dart';
import '../auth/login_screen.dart';
import '../auth/registration_screen.dart';
import 'my_orders_screen.dart';
import '../app_route.dart';

/// Front door for order tracking from the main bottom nav: the signed-in
/// customer's order history, or a prompt to sign in.
///
/// Signed-out visitors used to get a "Track a guest order" lookup by order
/// ID and phone number. Ordering has needed an account for some time, so
/// that lookup only ever served old guest orders, and it was removed along
/// with the server's guest paths (supabase/patch_signed_in_ordering.sql).
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
        title: 'Your orders',
        message: 'Sign in to order water and follow your deliveries.',
        action: PortalActionRow(
          children: [
            FilledButton(
              onPressed: () => Navigator.push(context, appRoute(const LoginScreen())),
              child: const Text('Sign in'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.push(context, appRoute(const RegistrationScreen())),
              child: const Text('Create account'),
            ),
          ],
        ),
      ),
    );
  }
}
