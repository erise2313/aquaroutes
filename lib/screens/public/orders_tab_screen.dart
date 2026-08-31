import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../providers/app_state.dart';
import '../auth/login_screen.dart';
import 'my_orders_screen.dart';
import 'track_order_screen.dart';

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

    if (isLoggedIn) {
      return const MyOrdersScreen();
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Orders')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.receipt_long_outlined, size: 56, color: Colors.blue.shade700),
              const SizedBox(height: 16),
              const Text(
                'Track a delivery or view your order history.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const TrackOrderScreen())),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14)),
                icon: const Icon(Icons.search, color: Colors.white),
                label: const Text('Track a Guest Order', style: TextStyle(color: Colors.white)),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const LoginScreen())),
                child: const Text('Log In to See Order History'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
