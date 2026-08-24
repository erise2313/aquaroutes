import 'package:flutter/material.dart';
import 'merchant_dashboard.dart';
import 'orders_screen.dart';
import 'tracking_screen.dart';
import 'merchant_profile_screens.dart';
import '../../widgets/responsive_nav_shell.dart';
import '../public/bulletin_board_screen.dart';

class MerchantNavigation extends StatelessWidget {
  const MerchantNavigation({super.key});

  @override
  Widget build(BuildContext context) {
    return ResponsiveNavShell(
      selectedItemColor: Colors.blue.shade700,
      destinations: const [
        NavShellDestination(icon: Icons.home_outlined, selectedIcon: Icons.home, label: 'Home'),
        NavShellDestination(icon: Icons.list_alt, label: 'Orders'),
        NavShellDestination(icon: Icons.map_outlined, selectedIcon: Icons.map, label: 'Track'),
        NavShellDestination(icon: Icons.campaign_outlined, selectedIcon: Icons.campaign, label: 'Board'),
        NavShellDestination(icon: Icons.person_outline, selectedIcon: Icons.person, label: 'Profile'),
      ],
      pages: const [
        MerchantDashboardScreen(),
        MerchantOrdersScreen(),
        TrackingScreen(),
        BulletinBoardScreen(),
        MerchantProfileScreen(),
      ],
    );
  }
}
