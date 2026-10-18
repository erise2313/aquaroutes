import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../constants/brand_tokens.dart';
import '../../screens/app_route.dart';
import '../responsive_nav_shell.dart';
import '../wasa_shield_logo.dart';

/// The station-owner and admin portals' shell.
///
/// **In a browser** it is a grouped left sidebar. The portals used to put
/// their sections in a top bar, and several pages (admin's Events, Resources
/// and Permits; the owner's Permit vault, Hire check, Clearinghouse...) were
/// not in it at all -- they could only be reached from tiles on the
/// dashboard. During the evaluation the tester struggled to find them. Now
/// every page is listed, under a heading saying what kind of page it is:
///
///  * 1100px and wider: the full 264px sidebar.
///  * 800-1100px: an icon rail with tooltips, so the content keeps its room.
///  * narrower: a menu button opening the same sidebar as a drawer.
///
/// Each section keeps its own navigation stack, so a screen opened from a
/// section (a station's permits, a worker's record) opens in the content
/// area with the sidebar still beside it, and choosing the active section
/// again returns to its first page.
///
/// **In the app** the sections stay in the bottom tab bar, as the app has
/// always had them. Destinations marked `phoneTab: false` go on a "More"
/// tab rather than squeezing a sixth or seventh tab in; ones marked
/// `onPhone: false` are web-only (the app reaches them from the dashboard).
class PortalShell extends StatefulWidget {
  const PortalShell({
    super.key,
    required this.destinations,
    required this.pages,
    required this.portalName,
    this.onBrandTap,
    this.footerActions = const [],
    this.selectedItemColor,
    this.maxContentWidth = 1100,
    @visibleForTesting this.webLayout,
  }) : assert(destinations.length == pages.length);

  final List<NavShellDestination> destinations;
  final List<Widget> pages;

  /// Shown under the wordmark: "Admin portal", "Station portal".
  final String portalName;

  /// Out of the portal and back to the public site, where there is one.
  final VoidCallback? onBrandTap;

  /// The sidebar's footer controls -- light/dark, notifications, account.
  final List<Widget> footerActions;

  final Color? selectedItemColor;

  /// Reading measure for the content area. Admin passes a wider one: its
  /// screens are tables, maps and charts rather than phone-shaped forms.
  final double maxContentWidth;

  /// Forces the browser layout on or off. `kIsWeb` is a compile-time
  /// constant (false under `flutter test`), so tests use this to reach the
  /// sidebar.
  final bool? webLayout;

  @override
  State<PortalShell> createState() => _PortalShellState();
}

class _PortalShellState extends State<PortalShell> {
  int _index = 0;
  late final List<GlobalKey<NavigatorState>> _navigatorKeys =
      List.generate(widget.pages.length, (_) => GlobalKey<NavigatorState>());

  bool get _isWeb => widget.webLayout ?? kIsWeb;

  void _select(int i) {
    if (i == _index) {
      // The usual sidebar behaviour: choosing the section you're in takes you
      // back to its first page.
      _navigatorKeys[i].currentState?.popUntil((r) => r.isFirst);
      return;
    }
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    return _isWeb ? _buildWeb(context) : _buildPhone(context);
  }

  // -- App ---------------------------------------------------------------

  Widget _buildPhone(BuildContext context) {
    final tabs = <NavShellDestination>[];
    final tabPages = <Widget>[];
    final more = <int>[];
    for (var i = 0; i < widget.destinations.length; i++) {
      final d = widget.destinations[i];
      if (!d.onPhone) continue;
      if (d.phoneTab) {
        tabs.add(d);
        tabPages.add(widget.pages[i]);
      } else {
        more.add(i);
      }
    }
    if (more.isNotEmpty) {
      final moreBadges = more.fold<int>(0, (sum, i) => sum + (widget.destinations[i].badgeCount ?? 0));
      tabs.add(NavShellDestination(
        icon: Icons.menu,
        selectedIcon: Icons.menu_open,
        label: 'More',
        badgeCount: moreBadges,
      ));
      tabPages.add(_MorePage(
        portalName: widget.portalName,
        // The same controls as the web sidebar's footer. Without them an
        // officer in the app had no way to sign out or change the theme.
        actions: widget.footerActions,
        entries: [for (final i in more) (widget.destinations[i], widget.pages[i])],
      ));
    }

    return ResponsiveNavShell(
      selectedItemColor: widget.selectedItemColor,
      destinations: tabs,
      pages: tabPages,
      maxContentWidth: widget.maxContentWidth,
    );
  }

  // -- Browser -----------------------------------------------------------

  bool _selectLabel(String label) {
    final i = widget.destinations.indexWhere((d) => d.label == label);
    if (i < 0) return false;
    // A section that was already open returns to its first page, so the
    // switch always lands on the list rather than wherever it was left.
    _navigatorKeys[i].currentState?.popUntil((r) => r.isFirst);
    if (i != _index) setState(() => _index = i);
    return true;
  }

  Widget _buildWeb(BuildContext context) {
    return PortalShellScope(selectLabel: _selectLabel, child: _buildWebLayout(context));
  }

  Widget _buildWebLayout(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final mode = width >= 1100
            ? _SidebarMode.expanded
            : width >= 800
                ? _SidebarMode.rail
                : _SidebarMode.drawer;

        final content = IndexedStack(
          index: _index,
          children: [
            for (var i = 0; i < widget.pages.length; i++)
              // Each section gets its own navigator so pushes stay inside the
              // content area.
              _SectionNavigator(
                navigatorKey: _navigatorKeys[i],
                maxContentWidth: widget.maxContentWidth,
                child: widget.pages[i],
              ),
          ],
        );

        Widget sidebar({required bool compact, VoidCallback? afterSelect}) => PortalSidebar(
              destinations: widget.destinations,
              selectedIndex: _index,
              compact: compact,
              portalName: widget.portalName,
              onBrandTap: widget.onBrandTap,
              footerActions: widget.footerActions,
              onSelect: (i) {
                _select(i);
                afterSelect?.call();
              },
            );

        if (mode == _SidebarMode.drawer) {
          return Scaffold(
            appBar: AppBar(
              titleSpacing: 0,
              title: _Wordmark(portalName: widget.portalName, onTap: widget.onBrandTap, compact: width < 420),
              actions: [...widget.footerActions, const SizedBox(width: 4)],
            ),
            drawer: Builder(
              builder: (drawerContext) => Drawer(
                width: 288,
                child: sidebar(compact: false, afterSelect: () => Navigator.of(drawerContext).pop()),
              ),
            ),
            body: content,
          );
        }

        return Scaffold(
          body: Row(
            children: [
              sidebar(compact: mode == _SidebarMode.rail),
              Expanded(child: content),
            ],
          ),
        );
      },
    );
  }
}

enum _SidebarMode { expanded, rail, drawer }

/// Lets a page inside the shell switch to another section -- a dashboard
/// tile saying "3 permits to review" should take you to Permits with the
/// sidebar showing where you are, not open a second copy of the page.
///
/// Only the browser layout registers it; in the app a section may live on
/// the More tab, so callers fall back to pushing the page:
///
/// ```dart
/// if (!PortalShellScope.select(context, 'Permits')) Navigator.push(...);
/// ```
class PortalShellScope extends InheritedWidget {
  const PortalShellScope({super.key, required this.selectLabel, required super.child});

  final bool Function(String label) selectLabel;

  /// Switches to the section called [label]. False when there is no shell
  /// to switch (the app) or no section by that name.
  static bool select(BuildContext context, String label) {
    final scope = context.getInheritedWidgetOfExactType<PortalShellScope>();
    return scope?.selectLabel(label) ?? false;
  }

  /// Whether [context] is inside the browser sidebar layout, whose footer
  /// already carries the light/dark switch and the notification bell. Page
  /// headers use it to avoid showing a second copy of either.
  static bool isPresent(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PortalShellScope>() != null;

  @override
  bool updateShouldNotify(PortalShellScope oldWidget) => false;
}

class _SectionNavigator extends StatelessWidget {
  const _SectionNavigator({required this.navigatorKey, required this.child, required this.maxContentWidth});

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;
  final double maxContentWidth;

  // No Theme wrapper here: the page inherits the portal's Theme through the
  // Navigator, so it follows the light/dark switch. It used to be wrapped in
  // a copy of the Theme taken when the section was first opened -- a route
  // builds its page once, so that copy never changed, and toggling left the
  // sidebar in one mode and every page already visited in the other.
  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      onGenerateRoute: (settings) => PageRouteBuilder(
        settings: settings,
        pageBuilder: (_, _, _) => Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxContentWidth),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// The grouped navigation list, shared by the expanded sidebar, the icon
/// rail and the drawer.
class PortalSidebar extends StatelessWidget {
  const PortalSidebar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelect,
    required this.portalName,
    this.compact = false,
    this.onBrandTap,
    this.footerActions = const [],
  });

  final List<NavShellDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final String portalName;
  final bool compact;
  final VoidCallback? onBrandTap;
  final List<Widget> footerActions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Consecutive destinations with the same group share one heading.
    final rows = <Widget>[];
    String? currentGroup;
    for (var i = 0; i < destinations.length; i++) {
      final d = destinations[i];
      if (d.group != currentGroup) {
        currentGroup = d.group;
        if (d.group != null) {
          rows.add(compact
              ? const Padding(padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16), child: Divider())
              : _GroupHeading(d.group!));
        }
      }
      rows.add(_SidebarItem(
        destination: d,
        selected: i == selectedIndex,
        compact: compact,
        onTap: () => onSelect(i),
      ));
    }

    return Material(
      color: scheme.surface,
      child: Container(
        width: compact ? 84 : 264,
        decoration: BoxDecoration(border: Border(right: BorderSide(color: scheme.outlineVariant))),
        child: SafeArea(
          right: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(compact ? 12 : 20, 20, 12, 12),
                child: _Wordmark(portalName: portalName, onTap: onBrandTap, compact: compact),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 12),
                  children: rows,
                ),
              ),
              if (footerActions.isNotEmpty) ...[
                Divider(height: 1, color: scheme.outlineVariant),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: compact
                      ? Column(mainAxisSize: MainAxisSize.min, children: footerActions)
                      : Wrap(alignment: WrapAlignment.spaceEvenly, children: footerActions),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupHeading extends StatelessWidget {
  const _GroupHeading(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 16, 6),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.4, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.destination,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final NavShellDestination destination;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = selected ? scheme.primary : scheme.onSurface;
    final count = destination.badgeCount ?? 0;
    final icon = Icon(selected ? (destination.selectedIcon ?? destination.icon) : destination.icon, color: fg);

    final tile = Semantics(
      selected: selected,
      button: true,
      label: count > 0 ? '${destination.label}, $count waiting' : destination.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(BrandRadius.control),
        child: Container(
          constraints: const BoxConstraints(minHeight: BrandType.minTarget),
          padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 12),
          decoration: BoxDecoration(
            color: selected ? scheme.primary.withValues(alpha: theme.brightness == Brightness.dark ? 0.22 : 0.10) : null,
            borderRadius: BorderRadius.circular(BrandRadius.control),
            // Gold marks "you are here" on every surface in the product.
            border: selected ? const Border(left: BorderSide(color: BrandColors.sealGold, width: 3)) : null,
          ),
          child: compact
              ? Center(child: count > 0 ? Badge.count(count: count, child: icon) : icon)
              : Row(
                  children: [
                    icon,
                    const SizedBox(width: 14),
                    Expanded(
                      child: ExcludeSemantics(
                        child: Text(
                          destination.label,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: fg,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    if (count > 0) _CountChip(count),
                  ],
                ),
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 12, vertical: 2),
      child: compact ? Tooltip(message: destination.label, child: tile) : tile,
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip(this.count);
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: scheme.error, borderRadius: BorderRadius.circular(BrandRadius.pill)),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: TextStyle(color: scheme.onError, fontWeight: FontWeight.w700, fontSize: BrandType.labelSmall),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.portalName, this.onTap, this.compact = false});

  final String portalName;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mark = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const WasaShieldLogo(size: 36),
        if (!compact) ...[
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GENTRI WASA',
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.fraunces(fontWeight: FontWeight.w600, fontSize: 18, color: theme.colorScheme.onSurface),
                ),
                Text(portalName, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelMedium),
              ],
            ),
          ),
        ],
      ],
    );
    return Semantics(
      label: 'GenTri WASA $portalName',
      child: onTap == null
          ? mark
          : InkWell(onTap: onTap, borderRadius: BorderRadius.circular(6), child: mark),
    );
  }
}

/// The app's "More" tab: the remaining sections, grouped the same way as the
/// website's sidebar so an officer who uses both finds things in one place.
class _MorePage extends StatelessWidget {
  const _MorePage({required this.portalName, required this.entries, this.actions = const []});

  final String portalName;
  final List<(NavShellDestination, Widget)> entries;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final children = <Widget>[];
    String? group;
    for (final (d, page) in entries) {
      if (d.group != group) {
        group = d.group;
        if (group != null) children.add(_GroupHeading(group));
      }
      final count = d.badgeCount ?? 0;
      children.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Card(
          child: ListTile(
            leading: Icon(d.icon),
            title: Text(d.label),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (count > 0) _CountChip(count),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () => Navigator.push(context, ambientRoute(context, page)),
          ),
        ),
      ));
    }

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(child: Text('More', style: theme.textTheme.headlineSmall)),
                  ...actions,
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Everything else in the $portalName', style: theme.textTheme.bodySmall),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}
