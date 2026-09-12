import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/web_theme.dart';
import '../web_router.dart';
import '../providers/app_state.dart';
import '../providers/web_locale_provider.dart';
import '../providers/web_theme_provider.dart';
import 'account_settings_section.dart';
import 'brand_top_bar.dart';
import 'web_page_route.dart';
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

/// The public website's top nav: the shared [BrandTopBar] carrying the site's
/// pages and its own trailing cluster (language, light/dark, and either
/// sign-in actions or the account menu).
///
/// The bar itself now lives in brand_top_bar.dart so the station-owner and
/// admin portals wear the same header rather than a Material NavigationRail.
/// Nav links use `context.go` (siblings, not a drill-down hierarchy) so
/// browsing the site doesn't pile up an ever-growing back stack.
class WebNavBar extends ConsumerWidget implements PreferredSizeWidget {
  const WebNavBar({super.key, required this.currentPage});

  final WebPage currentPage;

  @override
  Size get preferredSize => const Size.fromHeight(80);

  /// The portal has its own URL, so signing in no longer swallows the public
  /// site: `/` stays the marketing home and `/portal` is the dashboard.
  void _goToPortal(BuildContext context) {
    if (GoRouter.maybeOf(context) != null) {
      context.go(WebRoutes.portal);
    }
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

  /// Opens the same account block every other signed-in surface uses
  /// (AdminPageHeader opens it identically), rather than inventing a second
  /// account surface for the website.
  void _openAccount(BuildContext context, String title) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
        content: const SizedBox(width: 420, child: AccountSettingsSection()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(webLocaleProvider);
    String t(String key) => WebStrings.t(locale, key);
    // Session, not membership: waiting for the role to resolve would flash
    // Login/Register on every page load for someone already signed in.
    final isSignedIn = ref.watch(isSignedInProvider);
    final palette = WebTheme.of(context);

    final pages = <(WebPage, String, Widget)>[
      (WebPage.home, t('nav_home'), const OrgHomeScreen()),
      (WebPage.about, t('nav_about'), const AboutScreen()),
      (WebPage.howItWorks, t('nav_how_it_works'), const HowAccreditationWorksScreen()),
      (WebPage.forOwners, t('nav_for_owners'), const ForStationOwnersScreen()),
      (WebPage.news, t('nav_news'), const NewsScreen()),
      (WebPage.stations, t('nav_stations'), const StationsDirectoryScreen()),
      (WebPage.contact, t('nav_contact'), const ContactScreen()),
    ];

    // Mirrors the actual widgets below, padding for padding, so this is a
    // measurement rather than a guess: guessing here is what silently clips
    // links when it runs low. It branches on which action set is rendered --
    // the signed-in pair is narrower than Login + Register a Station.
    const bold14 = TextStyle(fontSize: 14, fontWeight: FontWeight.w600);
    const code13 = TextStyle(fontSize: 13, fontWeight: FontWeight.w700);
    final toggleWidth = 20 +
        BrandTopBar.measureText('EN', code13) +
        BrandTopBar.measureText('  |  ', const TextStyle(fontSize: 13)) +
        BrandTopBar.measureText('TL', code13);
    final signedInActionsWidth = 44 + 8 + 40 + BrandTopBar.measureText(t('nav_dashboard'), bold14);
    final signedOutActionsWidth = 32 +
        BrandTopBar.measureText(t('nav_login'), bold14) +
        8 +
        40 +
        BrandTopBar.measureText(t('nav_register'), bold14);
    final actionsWidth = 12 + // gap before the toggle
        toggleWidth +
        44 + // light/dark toggle button
        21 + // divider + its margins
        (isSignedIn ? signedInActionsWidth : signedOutActionsWidth);

    return BrandTopBar(
      onBrandTap: () => _go(context, WebPage.home, const OrgHomeScreen()),
      menuTooltip: t('nav_menu_tooltip'),
      background: palette.paper,
      foreground: palette.ink,
      borderColor: palette.border,
      activeColor: WebTheme.harborBlue,
      underlineColor: WebTheme.sealGold,
      actionsWidth: actionsWidth,
      links: [
        for (final page in pages)
          BrandNavLink(
            label: page.$2,
            isActive: page.$1 == currentPage,
            onTap: () => _go(context, page.$1, page.$3),
          ),
      ],
      actionsBuilder: (context, layout) => [
        if (!layout.compact) const SizedBox(width: 12),
        _LocaleToggle(
          locale: locale,
          compact: layout.compact,
          onTap: () => ref.read(webLocaleProvider.notifier).toggle(),
        ),
        WebThemeToggle(
          isDark: palette.isDark,
          color: palette.ink,
          onTap: () => ref.read(webThemeProvider.notifier).toggle(),
        ),
        // Separates "site preference" from "your account" -- the bare text
        // buttons read as one undifferentiated cluster otherwise. Wide only:
        // on a phone the row has no width to spare for a rule plus margins.
        if (!layout.compact)
          Container(
            width: 1,
            height: 22,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            color: palette.border,
          ),
        if (isSignedIn) ...[
          PopupMenuButton<String>(
            tooltip: t('nav_account_tooltip'),
            icon: Icon(Icons.account_circle_outlined, color: palette.ink),
            onSelected: (value) {
              if (value == 'account') {
                _openAccount(context, t('nav_account'));
              } else {
                Supabase.instance.client.auth.signOut();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'account',
                child: ListTile(
                  leading: const Icon(Icons.manage_accounts_outlined),
                  title: Text(t('nav_account')),
                ),
              ),
              PopupMenuItem(
                value: 'signout',
                child: ListTile(
                  leading: const Icon(Icons.logout),
                  title: Text(t('nav_sign_out')),
                ),
              ),
            ],
          ),
          if (layout.hasRoomForPrimary) ...[
            const SizedBox(width: 8),
            // The way back into the portal, and the counterpart to the brand
            // mark being the way back out of it.
            ElevatedButton(
              onPressed: () => _goToPortal(context),
              style: _primaryButtonStyle,
              child: Text(t('nav_dashboard')),
            ),
          ],
        ] else ...[
          TextButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const LoginScreen())),
            style: TextButton.styleFrom(
              foregroundColor: palette.ink,
              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              padding: EdgeInsets.symmetric(horizontal: layout.compact ? 8 : 16),
            ),
            child: Text(t('nav_login')),
          ),
          if (layout.hasRoomForPrimary) ...[
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const RegistrationScreen())),
              style: _primaryButtonStyle,
              child: Text(t('nav_register')),
            ),
          ],
        ],
      ],
    );
  }

  static final ButtonStyle _primaryButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: WebTheme.harborBlue,
    foregroundColor: Colors.white,
    elevation: 0,
    padding: const EdgeInsets.symmetric(horizontal: 20),
    minimumSize: const Size(0, 44),
    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
  );
}

/// Light/dark switch. An icon showing the mode you'd switch TO, with a
/// tooltip saying so -- a sun icon while already in light mode reads as
/// "you are in light mode" to some people and "press for light" to others,
/// and the tooltip is what settles it.
///
/// Public because the portals put the same control in the same place on the
/// shared bar; they just drive a different provider.
class WebThemeToggle extends StatelessWidget {
  const WebThemeToggle({super.key, required this.isDark, required this.onTap, required this.color});

  final bool isDark;
  final VoidCallback onTap;
  final Color color;

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
          color: color,
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
