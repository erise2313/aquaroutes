import 'package:flutter/material.dart';

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

  const NavShellDestination({
    required this.icon,
    this.selectedIcon,
    required this.label,
    this.badgeCount,
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
  });

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
                  onDestinationSelected: (i) => setState(() => _currentIndex = i),
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

        return Scaffold(
          appBar: widget.appBar,
          body: IndexedStack(index: _currentIndex, children: widget.pages),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (i) => setState(() => _currentIndex = i),
            type: BottomNavigationBarType.fixed,
            selectedItemColor: widget.selectedItemColor,
            unselectedItemColor: Colors.grey,
            items: widget.destinations
                .map((d) => BottomNavigationBarItem(
                      icon: _badged(d, Icon(d.icon)),
                      activeIcon: _badged(d, Icon(d.selectedIcon ?? d.icon)),
                      label: d.label,
                    ))
                .toList(),
          ),
        );
      },
    );
  }
}
