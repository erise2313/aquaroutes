import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_dashboard.dart';
import 'bulletin_editor_screen.dart';
import 'station_accreditation_screen.dart';
import 'user_management_screen.dart';
import 'worker_clearance_screen.dart';
import '../../widgets/responsive_nav_shell.dart';

/// WASA Admin Portal shell.
class AdminNavigation extends StatelessWidget {
  const AdminNavigation({super.key});

  Future<void> _signOut(BuildContext context) async {
    await Supabase.instance.client.auth.signOut();
    if (!context.mounted) return;
    // AuthGate (the app's root widget) reacts to the resulting auth-state
    // change and shows LoginScreen itself.
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveNavShell(
      appBar: AppBar(
        title: const Text('GENTRI WASA Admin', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          IconButton(icon: const Icon(Icons.logout), tooltip: 'Sign Out', onPressed: () => _signOut(context)),
        ],
      ),
      selectedItemColor: Colors.indigo,
      destinations: const [
        NavShellDestination(icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard, label: 'Overview'),
        NavShellDestination(icon: Icons.verified_outlined, selectedIcon: Icons.verified, label: 'Stations'),
        NavShellDestination(icon: Icons.badge_outlined, selectedIcon: Icons.badge, label: 'Workers'),
        NavShellDestination(icon: Icons.campaign_outlined, selectedIcon: Icons.campaign, label: 'Bulletin'),
        NavShellDestination(icon: Icons.people_outline, selectedIcon: Icons.people, label: 'Users'),
      ],
      pages: const [
        AdminDashboardScreen(),
        StationAccreditationScreen(),
        WorkerClearanceScreen(),
        BulletinEditorScreen(),
        UserManagementScreen(),
      ],
    );
  }
}
