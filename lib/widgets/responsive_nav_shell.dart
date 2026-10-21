import 'package:flutter/material.dart';

import 'portal/portal_back.dart';

/// One tab's icon/label, platform-agnostic between BottomNavigationBar
/// (narrow) and NavigationRail (wide) representations.
class NavShellDestination {
  final IconData icon;
  final IconData? selectedIcon;
  final String label;

  /// Pending-work count shown as a badge on the tab. Null (or 0) draws no
  /// badge at all -- so a portal that doesn't track backlogs is unaffected.
  /// Without this an admin only learns a queue has items by opening the tab
  /// and reading it.
  final int? badgeCount;

  /// Sidebar group heading this destination sits under on the web portals
  /// ("Compliance", "Content"...). Null for top-level items such as Overview.
  final String? group;

  /// Whether the destination is a bottom tab in the app. Destinations with
  /// this false are listed on a "More" tab instead, so a phone never has to
  /// fit more than five tabs.
  final bool phoneTab;

  /// Whether the destination exists in the app at all. Some web sidebar
  /// entries (the owner's Permit vault, Hire check...) are reached from the
  /// dashboard on a phone, which is how the app has always worked.
  final bool onPhone;

  const NavShellDestination({
    required this.icon,
    this.selectedIcon,
    required this.label,
    this.badgeCount,
    this.group,
    this.phoneTab = true,
    this.onPhone = true,
  });
}

/// Shared responsive navigation shell for MerchantNavigation and
/// AdminNavigation -- both used a phone-only BottomNavigationBar, which
/// doesn't make sense on a wide browser window (the whole reason the web
/// build exists). Swaps to a Material NavigationRail above [wideBreakpoint]
/// and falls back to the existing bottom nav below it, so both portal
/// shells adapt without being rebuilt from scratch. Owns the tab-index
/// state itself so callers just hand it destinations + pages.
class ResponsiveNavShell extends StatefulWidget {
  const ResponsiveNavShell({
    super.key,
    this.appBar,
    required this.destinations,
    required this.pages,
    this.selectedItemColor,
    this.wideBreakpoint = 800,
    this.maxContentWidth = 1000,
    this.backController,
  });

  /// When given, switching tabs is recorded so Back returns to the tab you
  /// came from (portal_back.dart).
  final PortalBackController? backController;

  final PreferredSizeWidget? appBar;
  final List<NavShellDestination> destinations;
  final List<Widget> pages;
  final Color? selectedItemColor;
  final double wideBreakpoint;

  /// Width the page content is clamped to on a wide window. 1000 suits the
  /// phone-shaped forms the merchant portal is built from; admin passes a
  /// wider measure because its screens are lists, maps and charts that were
  /// being squeezed into a phone column with the right half of the monitor
  /// left empty.
  final double maxContentWidth;

  @override
  State<ResponsiveNavShell> createState() => _ResponsiveNavShellState();
}

class _ResponsiveNavShellState extends State<ResponsiveNavShell> {
  int _currentIndex = 0;

  void _selectTab(int i) {
    if (i == _currentIndex) return;
    widget.backController?.recordSection(_currentIndex, (previous) {
      if (mounted) setState(() => _currentIndex = previous);
    });
    setState(() => _currentIndex = i);
  }

  /// Wraps a destination icon in a count badge, or returns it untouched when
  /// there's nothing pending -- a badge showing "0" would be worse than none.
  Widget _badged(NavShellDestination d, Widget icon) {
    final count = d.badgeCount ?? 0;
    if (count <= 0) return icon;
    return Badge.count(count: count, child: icon);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= widget.wideBreakpoint;

        if (isWide) {
          return Scaffold(
            appBar: widget.appBar,
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _currentIndex,
                  onDestinationSelected: _selectTab,
                  labelType: NavigationRailLabelType.all,
                  selectedIconTheme: IconThemeData(color: widget.selectedItemColor),
                  destinations: widget.destinations
                      .map((d) => NavigationRailDestination(
                            icon: _badged(d, Icon(d.icon)),
                            selectedIcon: _badged(d, Icon(d.selectedIcon ?? d.icon)),
                            label: Text(d.label),
                          ))
                      .toList(),
                ),
                const VerticalDivider(width: 1),
                // Centered, max-width content so phone-designed forms
                // (registration, permit upload) don't stretch full-width
                // on a desktop monitor.
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: widget.maxContentWidth),
                      child: IndexedStack(index: _currentIndex, children: widget.pages),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final navTheme = Theme.of(context).bottomNavigationBarTheme;
        final crowded = MediaQuery.sizeOf(context).width / widget.destinations.length < 72;
        return Scaffold(
          appBar: widget.appBar,
          body: IndexedStack(index: _currentIndex, children: widget.pages),
          // The tab bar is the one place large system text has to be reined
          // in: past ~130% the labels push the tabs apart and clip. Every
          // other surface scales freely.
          bottomNavigationBar: MediaQuery.withClampedTextScaling(
            // Five or six tabs on a narrow phone have about 60 dp each: at
            // 130% "Products" became "Produ...", so the labels stay at the
            // normal size there.
            maxScaleFactor: widget.destinations.length > 4 && MediaQuery.sizeOf(context).width < 420 ? 1.0 : 1.3,
            child: BottomNavigationBar(
            // Even at the normal size, six 16 sp labels in ~60 dp tabs cut
            // "Products" short; crowded bars get a smaller label instead.
            selectedFontSize: crowded ? 12.5 : 14,
            unselectedFontSize: crowded ? 12.5 : 12,
            selectedLabelStyle: crowded ? navTheme.selectedLabelStyle?.copyWith(fontSize: 12.5) : null,
            unselectedLabelStyle: crowded ? navTheme.unselectedLabelStyle?.copyWith(fontSize: 12.5) : null,
            currentIndex: _currentIndex,
            onTap: _selectTab,
            type: BottomNavigationBarType.fixed,
            selectedItemColor: widget.selectedItemColor,
            unselectedItemColor: Theme.of(context).colorScheme.onSurfaceVariant,
            items: widget.destinations
                .map((d) => BottomNavigationBarItem(
                      icon: _badged(d, Icon(d.icon)),
                      activeIcon: _badged(d, Icon(d.selectedIcon ?? d.icon)),
                      label: d.label,
                    ))
                .toList(),
            ),
          ),
        );
      },
    );
  }
}
