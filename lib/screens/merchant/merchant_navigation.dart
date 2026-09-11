import 'package:flutter/material.dart';
import 'merchant_dashboard.dart';
import 'orders_screen.dart';
import 'tracking_screen.dart';
import 'merchant_profile_screens.dart';
import 'products_screen.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_theme.dart';
import '../../widgets/responsive_nav_shell.dart';
import '../public/bulletin_board_screen.dart';

/// Station owner portal shell.
class MerchantNavigation extends StatelessWidget {
  const MerchantNavigation({super.key});

  @override
  Widget build(BuildContext context) {
    // Pinned to the app's light theme rather than inheriting the root one.
    // main.dart drives the root theme from the website's dark-mode toggle, and
    // these screens are written for a light background -- without this, a
    // visitor who switched the public site to dark and then signed in as a
    // station owner got white cards and grey text on a dark page, with no
    // toggle in this portal to undo it. Screens pushed from here need
    // appRoute() (screens/app_route.dart) to keep it.
    return Theme(
      data: AppTheme.light,
      child: ResponsiveNavShell(
        selectedItemColor: AppColors.primary,
        // Products sits right after Orders: it's the second thing an owner
        // needs (a station can't take orders until it lists one), and it
        // used to be buried as chips under Profile > Station Info.
        destinations: const [
          NavShellDestination(icon: Icons.home_outlined, selectedIcon: Icons.home, label: 'Home'),
          NavShellDestination(icon: Icons.list_alt, label: 'Orders'),
          NavShellDestination(icon: Icons.sell_outlined, selectedIcon: Icons.sell, label: 'Products'),
          NavShellDestination(icon: Icons.map_outlined, selectedIcon: Icons.map, label: 'Track'),
          NavShellDestination(icon: Icons.campaign_outlined, selectedIcon: Icons.campaign, label: 'Board'),
          NavShellDestination(icon: Icons.person_outline, selectedIcon: Icons.person, label: 'Profile'),
        ],
        pages: const [
          MerchantDashboardScreen(),
          MerchantOrdersScreen(),
          ProductsScreen(),
          TrackingScreen(),
          BulletinBoardScreen(),
          MerchantProfileScreen(),
        ],
      ),
    );
  }
}
