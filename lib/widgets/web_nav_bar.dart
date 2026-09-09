import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/web_theme.dart';
import '../web_router.dart';
import '../providers/web_locale_provider.dart';
import '../providers/web_theme_provider.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/registration_screen.dart';
import '../screens/web/about_screen.dart';
import '../screens/web/contact_screen.dart';
import '../screens/web/for_station_owners_screen.dart';
import '../screens/web/how_accreditation_works_screen.dart';
import '../screens/web/news_screen.dart';
import '../screens/web/org_home_screen.dart';
import '../screens/web/stations_directory_screen.dart';
import '../web_strings.dart';
import 'wasa_shield_logo.dart';
import 'web_page_route.dart';

/// Which top-level website page is currently showing -- drives the active
/// nav-link highlight and which page pushReplacement navigates to.
enum WebPage {
  home,
  about,
  howItWorks,
  forOwners,
  news,
  stations,
  contact,
  // Footer-only pages -- not in the main nav `links` list below, so these
  // never match a nav-link highlight; they exist purely so each screen can
  // pass a distinct `currentPage` instead of incorrectly claiming `home`.
  faq,
  verifyAccreditation,
  jugClearinghouse,
  resources,
  events,
}

/// Shared sticky top nav for every public website page (screens/web/*.dart).
/// Not Flutter's AppBar widget directly -- a plain Container implementing
/// PreferredSizeWidget so nav links can wrap/collapse responsively, which
/// AppBar's fixed title+actions layout doesn't handle well. Nav links use
/// pushReplacement (siblings, not a drill-down hierarchy) so browsing the
/// site doesn't pile up an ever-growing back stack; only teaser links to a
/// dedicated page (e.g. Home's "View All") behave the same way for
/// consistency.
class WebNavBar extends ConsumerWidget implements PreferredSizeWidget {
  const WebNavBar({super.key, required this.currentPage});

  final WebPage currentPage;

  /// Taller than Material's default 56/64 on purpose: this is a public
  /// association site whose visitors skew older, and the extra height buys
  /// real breathing room around the brand mark and a full-size Register
  /// button rather than a cramped strip.
  @override
  Size get preferredSize => const Size.fromHeight(80);

  /// Wider than the 1100 column the page sections below use. Matching that
  /// column exactly looked tidy but left only ~600px for seven nav links, so
  /// "For Station Owners" got clipped mid-word and News/Stations/Contact fell
  /// off entirely. The nav carries more content than a prose column does, so
  /// it gets its own wider measure; centring both still reads as one aligned
  /// header rather than the old full-bleed row with a dead pocket on the right.
  static const double _maxContentWidth = 1500;
  static const double _gutter = 24;

  static double _textWidth(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return painter.width;
  }

  /// Width the full link row needs, measured from the labels actually being
  /// rendered. A fixed pixel breakpoint can't work here: the Tagalog labels
  /// ("Para sa May-ari ng Istasyon") run far wider than the English ones, so
  /// any threshold tuned for one locale clips the other. Measured at the bold
  /// weight so the row doesn't resize when the active page changes.
  static double _linksWidth(List<(WebPage, String, Widget)> links) {
    const style = TextStyle(fontSize: 14, fontWeight: FontWeight.w700);
    var total = 0.0;
    for (final link in links) {
      total += _textWidth(link.$2, style) + 24; // button padding + margin
    }
    return total;
  }

  /// Navigates by URL so every page is bookmarkable and shareable, and the
  /// browser's own back/forward buttons work. [screen] is kept for the
  /// non-routed builds (the mobile app's info screens reuse these widgets),
  /// where there is no GoRouter to fall back on.
  void _go(BuildContext context, WebPage page, Widget screen) {
    if (page == currentPage) return;
    final path = WebRoutes.forPage[page];
    if (path != null && GoRouter.maybeOf(context) != null) {
      context.go(path);
      return;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
    Navigator.of(context).push(webPageRoute(screen));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(webLocaleProvider);
    String t(String key) => WebStrings.t(locale, key);

    final links = <(WebPage, String, Widget)>[
      (WebPage.home, t('nav_home'), const OrgHomeScreen()),
      (WebPage.about, t('nav_about'), const AboutScreen()),
      (WebPage.howItWorks, t('nav_how_it_works'), const HowAccreditationWorksScreen()),
      (WebPage.forOwners, t('nav_for_owners'), const ForStationOwnersScreen()),
      (WebPage.news, t('nav_news'), const NewsScreen()),
      (WebPage.stations, t('nav_stations'), const StationsDirectoryScreen()),
      (WebPage.contact, t('nav_contact'), const ContactScreen()),
    ];

    return Container(
      decoration: BoxDecoration(
        color: WebTheme.of(context).paper,
        border: Border(bottom: BorderSide(color: WebTheme.of(context).border, width: 1)),
      ),
      child: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxContentWidth),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: _gutter),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Everything that isn't the link row, measured the same way,
                  // so the decision below is "do the links actually fit?"
                  // rather than a guess.
                  final brandWidth = 32 + 10 + _textWidth('GENTRI WASA', GoogleFonts.fraunces(fontSize: 19, fontWeight: FontWeight.w600)) + 12;
                  // Mirrors the actual widgets below, padding for padding, so
                  // this is a measurement rather than a guess: guessing here
                  // is what silently clips links when it runs low.
                  const bold14 = TextStyle(fontSize: 14, fontWeight: FontWeight.w600);
                  const code13 = TextStyle(fontSize: 13, fontWeight: FontWeight.w700);
                  final toggleWidth = 20 + _textWidth('EN', code13) + _textWidth('  |  ', const TextStyle(fontSize: 13)) + _textWidth('TL', code13);
                  final actionsWidth = 12 + // gap before the toggle
                      toggleWidth +
                      44 + // light/dark toggle button
                      21 + // divider + its margins
                      32 + _textWidth(t('nav_login'), bold14) +
                      8 + 40 + _textWidth(t('nav_register'), bold14);

                  final isWide = constraints.maxWidth >= brandWidth + 20 + _linksWidth(links) + actionsWidth + 16;
                  // The Register CTA is the site's primary conversion and
                  // needs far less room than seven links -- keep it once the
                  // links have collapsed to the menu, and only drop it when
                  // even the compact row can't hold it.
                  final showRegister = isWide || constraints.maxWidth >= brandWidth + 48 + actionsWidth + 24;
                  final compact = constraints.maxWidth < 700;
                  return Row(
                    children: [
                      // Bounded rather than Flexible: as a flex child the
                      // brand claimed an equal share of the row's free space
                      // and then used only part of it, and Row leaves that
                      // unused remainder at the *end* -- which is the dead
                      // space that showed up to the right of "Register a
                      // Station". Capping it keeps the wordmark able to
                      // ellipsize without letting it hoard slack that belongs
                      // to the link row.
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.45),
                        child: InkWell(
                          onTap: () => _go(context, WebPage.home, const OrgHomeScreen()),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            // Vertical only: any horizontal inset here would
                            // push the shield off the 1100 content column the
                            // hero headline below starts on.
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const WasaShieldLogo(size: 32),
                                // Below ~420px the wordmark would ellipsize to
                                // a couple of letters anyway; the shield alone
                                // reads better and gives the row back ~110px.
                                if (constraints.maxWidth >= 420) ...[
                                  const SizedBox(width: 10),
                                  Flexible(
                                    child: Text(
                                      'GENTRI WASA',
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.fraunces(fontWeight: FontWeight.w600, fontSize: 19, color: WebTheme.of(context).ink),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: compact ? 6 : 20),
                      if (isWide)
                        // Centered inside the slack rather than left-aligned:
                        // hugging the logo left every bit of leftover width in
                        // one pocket next to the actions, which is what made
                        // the bar look lopsided on wide screens.
                        Expanded(
                          child: Center(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: links
                                    .map((l) => _NavLink(
                                          label: l.$2,
                                          isActive: l.$1 == currentPage,
                                          onTap: () => _go(context, l.$1, l.$3),
                                        ))
                                    .toList(),
                              ),
                            ),
                          ),
                        )
                      else
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: PopupMenuButton<int>(
                              icon: Icon(Icons.menu, color: WebTheme.of(context).ink),
                              tooltip: t('nav_menu_tooltip'),
                              onSelected: (i) => _go(context, links[i].$1, links[i].$3),
                              itemBuilder: (context) => [
                                for (var i = 0; i < links.length; i++) PopupMenuItem(value: i, child: Text(links[i].$2)),
                              ],
                            ),
                          ),
                        ),
                      if (!compact) const SizedBox(width: 12),
                      _LocaleToggle(
                        locale: locale,
                        compact: compact,
                        onTap: () => ref.read(webLocaleProvider.notifier).toggle(),
                      ),
                      _ThemeToggle(
                        isDark: WebTheme.of(context).isDark,
                        onTap: () => ref.read(webThemeProvider.notifier).toggle(),
                      ),
                      // Separates "site preference" from "your account" -- the
                      // bare text buttons read as one undifferentiated cluster
                      // otherwise. Wide only: on a phone the row has no width
                      // to spare for a rule plus its margins.
                      if (!compact)
                        Container(
                          width: 1,
                          height: 22,
                          margin: const EdgeInsets.symmetric(horizontal: 10),
                          color: WebTheme.of(context).border,
                        ),
                      TextButton(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const LoginScreen())),
                        style: TextButton.styleFrom(
                          foregroundColor: WebTheme.of(context).ink,
                          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                          padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 16),
                        ),
                        child: Text(t('nav_login')),
                      ),
                      if (showRegister) ...[
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const RegistrationScreen())),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: WebTheme.harborBlue,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            minimumSize: const Size(0, 44),
                            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          child: Text(t('nav_register')),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Light/dark switch. An icon showing the mode you'd switch TO, with a
/// tooltip saying so -- a sun icon while already in light mode reads as
/// "you are in light mode" to some people and "press for light" to others,
/// and the tooltip is what settles it.
class _ThemeToggle extends StatelessWidget {
  const _ThemeToggle({required this.isDark, required this.onTap});

  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
      iconSize: 20,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, animation) => RotationTransition(
          turns: Tween<double>(begin: 0.75, end: 1).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: Icon(
          isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
          key: ValueKey(isDark),
          color: WebTheme.of(context).ink,
        ),
      ),
    );
  }
}

/// EN | TL, with the active language weighted and the other muted -- the old
/// version rendered both codes identically, so the control showed the choice
/// without ever showing which one you were currently reading.
class _LocaleToggle extends StatelessWidget {
  const _LocaleToggle({required this.locale, required this.onTap, this.compact = false});

  final WebLocale locale;
  final VoidCallback onTap;

  /// Phone widths: tighten the padding and the separator so the toggle,
  /// Login, and the brand mark all still fit on one row.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    TextStyle styleFor(WebLocale l) => TextStyle(
          fontSize: 13,
          fontWeight: l == locale ? FontWeight.w700 : FontWeight.w400,
          color: l == locale ? WebTheme.of(context).ink : WebTheme.of(context).ink.withValues(alpha: 0.45),
        );

    final target = locale == WebLocale.en ? WebLocale.tl : WebLocale.en;
    return Tooltip(
      message: WebStrings.t(locale, target == WebLocale.tl ? 'nav_switch_to_tl' : 'nav_switch_to_en'),
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 10),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          child: Row(
            key: ValueKey(locale),
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('EN', style: styleFor(WebLocale.en)),
              Text(
                compact ? ' | ' : '  |  ',
                style: TextStyle(fontSize: 13, color: WebTheme.of(context).ink.withValues(alpha: 0.3)),
              ),
              Text('TL', style: styleFor(WebLocale.tl)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavLink extends StatefulWidget {
  const _NavLink({required this.label, required this.isActive, required this.onTap});

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  State<_NavLink> createState() => _NavLinkState();
}

class _NavLinkState extends State<_NavLink> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.isActive ? WebTheme.harborBlue : (_hovering ? WebTheme.harborBlue.withValues(alpha: 0.7) : WebTheme.of(context).ink);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: TextButton(
          onPressed: widget.onTap,
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 150),
                style: TextStyle(color: color, fontWeight: widget.isActive ? FontWeight.w700 : FontWeight.w500, fontSize: 14),
                child: Text(widget.label),
              ),
              const SizedBox(height: 4),
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: 2.5,
                width: widget.isActive ? 22 : 0,
                decoration: BoxDecoration(color: WebTheme.sealGold, borderRadius: BorderRadius.circular(1)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
