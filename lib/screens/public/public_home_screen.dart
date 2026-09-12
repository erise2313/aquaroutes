import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants/app_colors.dart';
import '../../models/membership.dart';
import '../../providers/app_state.dart';
import '../../widgets/app_theme_toggle.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/wasa_shield_logo.dart';
import '../auth/login_screen.dart';
import '../auth/registration_screen.dart';
import 'bulletin_feed.dart';
import '../../providers/app_theme_provider.dart';
import '../app_route.dart';
import 'customer_account_screen.dart';
import 'customer_home_screen.dart';
import 'info/about_wasa_hub_screen.dart';
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
  // Named rather than bare indices: the Home tab hands off to three of these,
  // and an off-by-one would silently send "Order water" to the map.
  static const _homeTab = 0;
  static const _boardTab = 1;
  static const _orderTab = 2;
  static const _mapTab = 3;

  /// The app opens on Home -- it used to open on the Bulletin Board.
  int _currentIndex = _homeTab;

  void _openTab(int index) => setState(() => _currentIndex = index);

  @override
  Widget build(BuildContext context) {
    final membership = ref.watch(currentMembershipProvider).value;
    final isSignedInCustomer = membership?.role == AppRole.publicConsumer;

    // Pinned to the app's light theme rather than inheriting the root one --
    // main.dart drives that from the website's dark-mode toggle, and these
    // screens are written for a light background. Screens pushed from here
    // need appRoute() (screens/app_route.dart) to keep it, since a
    // MaterialPageRoute builds above this Theme, not under it.
    return Theme(
      data: appThemeDataFor(ref.watch(appThemeProvider), MediaQuery.platformBrightnessOf(context)),
      child: Builder(builder: (context) {
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
        actions: [
          const AppThemeToggle(),
          if (isSignedInCustomer) const NotificationBell(),
          IconButton(
            tooltip: 'About WASA',
            icon: Icon(Icons.info_outline, color: onSurface),
            onPressed: () => Navigator.push(context, appRoute(const AboutWasaHubScreen())),
          ),
          ...isSignedInCustomer
            ? [
                IconButton(
                  tooltip: 'My Account',
                  icon: Icon(Icons.account_circle_outlined, color: onSurface),
                  onPressed: () => Navigator.push(context, appRoute(const CustomerAccountScreen())),
                ),
                const SizedBox(width: 8),
              ]
            : [
                TextButton(
                  onPressed: () => Navigator.push(context, appRoute(const LoginScreen())),
                  child: const Text('Login'),
                ),
                TextButton(
                  onPressed: () => Navigator.push(context, appRoute(const RegistrationScreen())),
                  child: const Text('Register'),
                ),
                const SizedBox(width: 8),
              ],
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          CustomerHomeScreen(
            onOrderWater: () => _openTab(_orderTab),
            onFindStation: () => _openTab(_mapTab),
            onOpenBoard: () => _openTab(_boardTab),
          ),
          const BulletinFeed(),
          const QuickOrderScreen(),
          const StationMapScreen(),
          const OrdersTabScreen(),
        ],
      ),
      bottomNavigationBar: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _openTab,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: Theme.of(context).colorScheme.onSurfaceVariant,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.campaign_outlined), activeIcon: Icon(Icons.campaign), label: 'Board'),
          BottomNavigationBarItem(icon: Icon(Icons.local_shipping_outlined), activeIcon: Icon(Icons.local_shipping), label: 'Order'),
          BottomNavigationBarItem(icon: Icon(Icons.map_outlined), activeIcon: Icon(Icons.map), label: 'Map'),
          BottomNavigationBarItem(icon: Icon(Icons.receipt_long_outlined), activeIcon: Icon(Icons.receipt_long), label: 'Orders'),
        ],
        ),
      ),
        );
      }),
    );
  }
}
