import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../providers/app_theme_provider.dart';
import '../../services/my_station.dart';
import '../../web_router.dart';
import '../../widgets/account_settings_section.dart';
import '../../widgets/app_theme_toggle.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/portal/portal.dart';
import '../../widgets/responsive_nav_shell.dart';
import '../merchant/driver_management.dart';
import '../merchant/orders_screen.dart';
import '../merchant/tracking_screen.dart';
import '../public/bulletin_board_screen.dart';

/// The station staff (dispatcher) portal.
///
/// Staff take orders, assign drivers and follow deliveries for the station
/// that invited them -- the owner's own Orders, Track and Drivers screens,
/// which find the station through the person's membership
/// (services/my_station.dart). Permits, prices, products, the worker
/// registry, settlements and the station profile stay with the owner, and
/// the database enforces that (supabase/patch_roles_governance.sql), not
/// just this menu.
class StaffNavigation extends StatelessWidget {
  const StaffNavigation({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final theme = appThemeDataFor(ref.watch(appThemeProvider), MediaQuery.platformBrightnessOf(context));
        return Theme(
          data: theme,
          child: Builder(
            builder: (context) => PortalShell(
              portalName: 'Station staff',
              selectedItemColor: Theme.of(context).colorScheme.primary,
              onBrandTap: () => _leavePortal(context),
              footerActions: [
                const AppThemeToggle(),
                const NotificationBell(),
                PortalAccountMenu(onLeavePortal: kIsWeb ? () => _leavePortal(context) : null),
              ],
              maxContentWidth: 1280,
              destinations: const [
                NavShellDestination(icon: Icons.list_alt, label: 'Orders'),
                NavShellDestination(icon: Icons.map_outlined, selectedIcon: Icons.map, label: 'Track', group: 'Deliveries'),
                NavShellDestination(icon: Icons.groups_outlined, selectedIcon: Icons.groups, label: 'Drivers', group: 'Deliveries'),
                NavShellDestination(icon: Icons.campaign_outlined, selectedIcon: Icons.campaign, label: 'Board', group: 'Network'),
                NavShellDestination(icon: Icons.person_outline, selectedIcon: Icons.person, label: 'Account', group: 'Account'),
              ],
              pages: const [
                MerchantOrdersScreen(),
                TrackingScreen(),
                DriverManagementScreen(readOnly: true),
                BulletinBoardScreen(showAppBar: false),
                StaffAccountScreen(),
              ],
            ),
          ),
        );
      },
    );
  }

  void _leavePortal(BuildContext context) {
    if (kIsWeb && GoRouter.maybeOf(context) != null) {
      context.go(WebRoutes.home);
    }
  }
}

/// Who the staff member is, which station they work for, and their settings.
class StaffAccountScreen extends StatefulWidget {
  const StaffAccountScreen({super.key});

  @override
  State<StaffAccountScreen> createState() => _StaffAccountScreenState();
}

class _StaffAccountScreenState extends State<StaffAccountScreen> {
  final _supabase = Supabase.instance.client;
  String? _stationName;
  String? _stationAddress;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final station = await fetchMyStation(_supabase, columns: 'station_name, station_address');
      if (mounted) {
        setState(() {
          _stationName = station?['station_name'] as String?;
          _stationAddress = station?['station_address'] as String?;
        });
      }
    } catch (_) {
      // The rest of the page still works without the station's name.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final density = PortalDensity.of(context);
    return Scaffold(
      body: Column(
        children: [
          const PortalPageHeader(eyebrow: 'Station staff', title: 'Account'),
          Expanded(
            child: ListView(
              padding: density.pagePadding,
              children: [
                PortalCard(
                  lift: false,
                  child: Row(
                    children: [
                      Icon(Icons.storefront_outlined, color: theme.colorScheme.primary),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('You work at', style: theme.textTheme.bodySmall),
                            Text(_stationName ?? '…', style: theme.textTheme.titleMedium),
                            if (_stationAddress != null) Text(_stationAddress!, style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'You can take orders, assign drivers and follow deliveries. Permits, prices, products and the '
                  'station profile are managed by the station owner.',
                  style: theme.textTheme.bodySmall,
                ),
                SizedBox(height: density.sectionGap),
                const PortalCard(lift: false, padding: EdgeInsets.zero, child: AccountSettingsSection()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
