import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../brand_top_bar.dart';
import '../responsive_nav_shell.dart';

/// The station-owner and admin portals' shell.
///
/// In a browser the portal now wears the same branded bar as the public
/// website, with its own sections as the nav links: a Material
/// NavigationRail beside a narrow column was the single biggest reason the
/// three surfaces read as different products, however much the screens
/// inside it were restyled.
///
/// On a phone -- in the browser or in the app -- the sections stay in the
/// bottom tab bar, which is where they belong on a small screen and what the
/// app has always had. `MerchantNavigation` is shared between the app and the
/// web build, so this branches on [kIsWeb] rather than replacing the shell
/// outright.
class PortalShell extends StatefulWidget {
  const PortalShell({
    super.key,
    required this.destinations,
    required this.pages,
    required this.onBrandTap,
    required this.background,
    required this.foreground,
    required this.borderColor,
    required this.activeColor,
    required this.underlineColor,
    required this.actionsBuilder,
    required this.actionsWidth,
    this.selectedItemColor,
    this.maxContentWidth = 1100,
    this.menuTooltip = 'Open menu',
  });

  final List<NavShellDestination> destinations;
  final List<Widget> pages;

  /// Out of the portal and back to the public site. The counterpart to the
  /// website bar's Dashboard button, and half of what fixes a portal you
  /// could get into but not out of.
  final VoidCallback onBrandTap;

  final Color background;
  final Color foreground;
  final Color borderColor;
  final Color activeColor;
  final Color underlineColor;

  /// The bar's trailing cluster -- light/dark, notifications, account.
  final List<Widget> Function(BuildContext context, BrandBarLayout layout) actionsBuilder;

  /// Measured by the caller with `BrandTopBar.measureText`, for the same
  /// reason the website measures its own.
  final double actionsWidth;

  final Color? selectedItemColor;

  /// The site's own section measure, so a dashboard doesn't sit in a
  /// narrower column than the marketing pages do.
  final double maxContentWidth;

  final String menuTooltip;

  @override
  State<PortalShell> createState() => _PortalShellState();
}

class _PortalShellState extends State<PortalShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    // The app keeps exactly the shell it has always had: bottom tabs, no top
    // bar, no brand row taking a fifth of a phone screen.
    if (!kIsWeb) {
      return ResponsiveNavShell(
        selectedItemColor: widget.selectedItemColor,
        destinations: widget.destinations,
        pages: widget.pages,
        maxContentWidth: widget.maxContentWidth,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Matches the website's own collapse point and ResponsiveNavShell's,
        // so the layout never changes shape at two different widths.
        final isWide = constraints.maxWidth >= 800;

        final bar = BrandTopBar(
          onBrandTap: widget.onBrandTap,
          menuTooltip: widget.menuTooltip,
          background: widget.background,
          foreground: widget.foreground,
          borderColor: widget.borderColor,
          activeColor: widget.activeColor,
          underlineColor: widget.underlineColor,
          actionsWidth: widget.actionsWidth,
          actionsBuilder: widget.actionsBuilder,
          // Narrow: the sections are in the bottom bar, so the top bar
          // carries the brand and the account only. Handing it the links
          // too would offer the same destinations twice.
          links: isWide
              ? [
                  for (var i = 0; i < widget.destinations.length; i++)
                    BrandNavLink(
                      label: widget.destinations[i].label,
                      isActive: i == _index,
                      onTap: () => setState(() => _index = i),
                    ),
                ]
              : const [],
        );

        return Scaffold(
          appBar: bar,
          body: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: widget.maxContentWidth),
              child: IndexedStack(index: _index, children: widget.pages),
            ),
          ),
          bottomNavigationBar: isWide
              ? null
              // The one place large system text has to be reined in: past
              // ~130% the labels push the tabs apart and clip. Every other
              // surface scales freely.
              : MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.3,
                  child: BottomNavigationBar(
                    currentIndex: _index,
                    onTap: (i) => setState(() => _index = i),
                    type: BottomNavigationBarType.fixed,
                    selectedItemColor: widget.selectedItemColor,
                    unselectedItemColor: widget.foreground.withValues(alpha: 0.6),
                    backgroundColor: widget.background,
                    items: [
                      for (final d in widget.destinations)
                        BottomNavigationBarItem(
                          icon: _badged(d, Icon(d.icon)),
                          activeIcon: _badged(d, Icon(d.selectedIcon ?? d.icon)),
                          label: d.label,
                        ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  /// A count badge, or the icon untouched when there's nothing pending -- a
  /// badge showing "0" would be worse than none.
  Widget _badged(NavShellDestination d, Widget icon) {
    final count = d.badgeCount ?? 0;
    if (count <= 0) return icon;
    return Badge.count(count: count, child: icon);
  }
}
