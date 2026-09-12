import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'merchant_dashboard.dart';
import 'orders_screen.dart';
import 'tracking_screen.dart';
import 'merchant_profile_screens.dart';
import 'products_screen.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_palette.dart';
import '../../providers/app_theme_provider.dart';
import '../../web_router.dart';
import '../../widgets/app_theme_toggle.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/portal/portal.dart';
import '../../widgets/responsive_nav_shell.dart';
import '../public/bulletin_board_screen.dart';

/// Station owner portal shell.
class MerchantNavigation extends StatelessWidget {
  const MerchantNavigation({super.key});

  @override
  Widget build(BuildContext context) {
    // Pinned to the app's own theme rather than inheriting the root one.
    // main.dart drives the root theme from the website's dark-mode toggle, and
    // these screens are written against AppPalette -- without this, a visitor
    // who switched the public site to dark and then signed in as a station
    // owner got white cards and grey text on a dark page. Screens pushed from
    // here need appRoute() (screens/app_route.dart) to keep it.
    return Consumer(
      builder: (context, ref, _) {
        final theme = appThemeDataFor(ref.watch(appThemeProvider), MediaQuery.platformBrightnessOf(context));
        final palette = theme.extension<AppPalette>() ?? AppPalette.light;

        return Theme(
          data: theme,
          child: Builder(
            // A Builder so the bar's actions resolve the Theme above rather
            // than the root one -- the toggle and the bell are painted on this
            // portal's surfaces, not the website's.
            builder: (context) => PortalShell(
              selectedItemColor: AppColors.primary,
              background: palette.paper,
              foreground: palette.ink,
              borderColor: palette.border,
              activeColor: AppColors.primary,
              // The association's gold marks "you are here" on every surface,
              // which is what ties the portal's bar to the website's.
              underlineColor: AppColors.seal,
              onBrandTap: () => _leavePortal(context),
              actionsWidth: _actionsWidth,
              actionsBuilder: (context, layout) => [
                if (!layout.compact) const SizedBox(width: 12),
                const AppThemeToggle(),
                const NotificationBell(),
              ],
              // Products sits right after Orders: it's the second thing an
              // owner needs (a station can't take orders until it lists one),
              // and it used to be buried as chips under Profile > Station Info.
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
                // The shell supplies the header here, so the wrapper's own
                // AppBar would be a second bar above the feed.
                BulletinBoardScreen(showAppBar: false),
                MerchantProfileScreen(),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Back out to the public site. Only the website build has a router -- in
  /// the app there is nowhere else to go, so the brand mark is inert there.
  void _leavePortal(BuildContext context) {
    if (kIsWeb && GoRouter.maybeOf(context) != null) {
      context.go(WebRoutes.home);
    }
  }

  /// The toggle and the bell are both 44px icon buttons, plus the gap before
  /// them. Measured on the same basis the website measures its own cluster,
  /// so the link row's fit decision stays a measurement rather than a guess.
  static const double _actionsWidth = 12 + 44 + 44;
}
