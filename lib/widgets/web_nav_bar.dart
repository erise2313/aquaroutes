import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_colors.dart';
import '../providers/web_locale_provider.dart';
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

  @override
  Size get preferredSize => const Size.fromHeight(64);

  void _go(BuildContext context, WebPage page, Widget screen) {
    if (page == currentPage) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => screen));
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
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 1000;
              return Row(
                children: [
                  InkWell(
                    onTap: () => _go(context, WebPage.home, const OrgHomeScreen()),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        WasaShieldLogo(size: 28),
                        SizedBox(width: 8),
                        Text('GenTri: WASA', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  if (isWide)
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: links
                              .map((l) => _NavLink(
                                    label: l.$2,
                                    isActive: l.$1 == currentPage,
                                    onTap: () => _go(context, l.$1, l.$3),
                                  ))
                              .toList(),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: PopupMenuButton<int>(
                          icon: const Icon(Icons.menu, color: Colors.black87),
                          onSelected: (i) => _go(context, links[i].$1, links[i].$3),
                          itemBuilder: (context) => [
                            for (var i = 0; i < links.length; i++) PopupMenuItem(value: i, child: Text(links[i].$2)),
                          ],
                        ),
                      ),
                    ),
                  TextButton(
                    onPressed: () => ref.read(webLocaleProvider.notifier).toggle(),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      child: Text(
                        locale == WebLocale.en ? 'EN | TL' : 'TL | EN',
                        key: ValueKey(locale),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const LoginScreen())),
                    child: Text(t('nav_login')),
                  ),
                  if (isWide)
                    ElevatedButton(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const RegistrationScreen())),
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                      child: Text(t('nav_register'), style: const TextStyle(color: Colors.white)),
                    ),
                ],
              );
            },
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
    final color = widget.isActive ? AppColors.primary : (_hovering ? AppColors.primary.withValues(alpha: 0.7) : Colors.black87);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: TextButton(
          onPressed: widget.onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 150),
                style: TextStyle(color: color, fontWeight: widget.isActive ? FontWeight.bold : FontWeight.normal, fontSize: 13),
                child: Text(widget.label),
              ),
              const SizedBox(height: 3),
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: 2,
                width: widget.isActive ? 18 : 0,
                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(1)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
