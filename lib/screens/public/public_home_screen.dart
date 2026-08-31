import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants/app_colors.dart';
import '../../models/membership.dart';
import '../../providers/app_state.dart';
import '../../widgets/wasa_shield_logo.dart';
import '../auth/login_screen.dart';
import '../auth/registration_screen.dart';
import 'bulletin_feed.dart';
import 'customer_account_screen.dart';
import 'orders_tab_screen.dart';
import 'quick_order_screen.dart';
import 'station_map_screen.dart';

/// Landing shell -- the default entry point for anyone opening the app,
/// logged in or not (AuthGate, screens/auth/auth_gate.dart). Browsing the
/// Board/Order/Map tabs never requires a session, but the app bar becomes
/// auth-aware: a signed-in customer (public_consumer membership) sees an
/// Account entry point instead of Login/Register. Quick Order itself
/// enforces the actual login requirement for placing an order (see
/// quick_order_screen.dart) -- this screen only swaps the app bar.
class PublicHomeScreen extends ConsumerStatefulWidget {
  const PublicHomeScreen({super.key});

  @override
  ConsumerState<PublicHomeScreen> createState() => _PublicHomeScreenState();
}

class _PublicHomeScreenState extends ConsumerState<PublicHomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    BulletinFeed(),
    QuickOrderScreen(),
    StationMapScreen(),
    OrdersTabScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final membership = ref.watch(currentMembershipProvider).value;
    final isSignedInCustomer = membership?.role == AppRole.publicConsumer;

    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Row(
          children: [
            const WasaShieldLogo(size: 32),
            const SizedBox(width: 10),
            Text('GenTri: WASA', style: TextStyle(fontWeight: FontWeight.bold, color: onSurface)),
          ],
        ),
        elevation: 0,
        iconTheme: IconThemeData(color: onSurface),
        actions: isSignedInCustomer
            ? [
                IconButton(
                  tooltip: 'My Account',
                  icon: Icon(Icons.account_circle_outlined, color: onSurface),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const CustomerAccountScreen())),
                ),
                const SizedBox(width: 8),
              ]
            : [
                TextButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const LoginScreen())),
                  child: const Text('Login'),
                ),
                TextButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const RegistrationScreen())),
                  child: const Text('Register'),
                ),
                const SizedBox(width: 8),
              ],
      ),
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.campaign_outlined), activeIcon: Icon(Icons.campaign), label: 'Board'),
          BottomNavigationBarItem(icon: Icon(Icons.local_shipping_outlined), activeIcon: Icon(Icons.local_shipping), label: 'Order'),
          BottomNavigationBarItem(icon: Icon(Icons.map_outlined), activeIcon: Icon(Icons.map), label: 'Map'),
          BottomNavigationBarItem(icon: Icon(Icons.receipt_long_outlined), activeIcon: Icon(Icons.receipt_long), label: 'Orders'),
        ],
      ),
    );
  }
}
