import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/web_theme.dart';
import '../web_router.dart';
import '../providers/web_locale_provider.dart';
import '../screens/web/about_screen.dart';
import '../screens/web/contact_screen.dart';
import '../screens/web/events_screen.dart';
import '../screens/web/faq_screen.dart';
import '../screens/web/jug_clearinghouse_explainer_screen.dart';
import '../screens/web/news_screen.dart';
import '../screens/web/resources_screen.dart';
import '../screens/web/stations_directory_screen.dart';
import '../screens/web/verify_accreditation_screen.dart';
import '../web_strings.dart';
import 'web_page_route.dart';
import 'web_seal.dart';

/// Shared footer for every public website page. Office address/hours are a
/// clearly-labeled placeholder -- no real WASA office details exist yet, so
/// this is deliberately marked "[Placeholder]" rather than a plausible-
/// looking invented address.
class WebFooter extends ConsumerWidget {
  const WebFooter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(webLocaleProvider);
    String t(String key) => WebStrings.t(locale, key);

    return Container(
      width: double.infinity,
      color: WebTheme.deepTeal,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 64,
                runSpacing: 24,
                children: [
                  SizedBox(
                    width: 260,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const WebSeal(size: 28),
                            const SizedBox(width: 10),
                            Text('GENTRI WASA', style: GoogleFonts.fraunces(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 18)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Water Station Association of General Trias, Cavite.',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t('footer_quick_links'), style: WebTheme.eyebrow.copyWith(fontSize: 11)),
                        const SizedBox(height: 12),
                        _FooterLink(label: t('nav_about'), onTap: () => _push(context, const AboutScreen(), WebRoutes.about)),
                        _FooterLink(label: t('nav_stations'), onTap: () => _push(context, const StationsDirectoryScreen(), WebRoutes.stations)),
                        _FooterLink(label: t('nav_news'), onTap: () => _push(context, const NewsScreen(), WebRoutes.news)),
                        _FooterLink(label: t('nav_contact'), onTap: () => _push(context, const ContactScreen(), WebRoutes.contact)),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t('footer_resources'), style: WebTheme.eyebrow.copyWith(fontSize: 11)),
                        const SizedBox(height: 12),
                        _FooterLink(label: t('faq_title'), onTap: () => _push(context, const FaqScreen(), WebRoutes.faq)),
                        _FooterLink(label: t('verify_title'), onTap: () => _push(context, const VerifyAccreditationScreen(), WebRoutes.verify)),
                        _FooterLink(label: t('jug_clearinghouse_title'), onTap: () => _push(context, const JugClearinghouseExplainerScreen(), WebRoutes.jugClearinghouse)),
                        _FooterLink(label: t('resources_title'), onTap: () => _push(context, const ResourcesScreen(), WebRoutes.resources)),
                        _FooterLink(label: t('events_title'), onTap: () => _push(context, const EventsScreen(), WebRoutes.events)),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 260,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t('footer_office'), style: WebTheme.eyebrow.copyWith(fontSize: 11)),
                        const SizedBox(height: 12),
                        const Text('[Placeholder] Association Office Address, General Trias, Cavite', style: TextStyle(color: Colors.white70, fontSize: 13)),
                        const SizedBox(height: 4),
                        const Text('[Placeholder] Office Hours: Mon-Fri, 8AM-5PM', style: TextStyle(color: Colors.white70, fontSize: 13)),
                        const SizedBox(height: 4),
                        _FooterLink(
                          label: 'contact@gentriwasa.example',
                          onTap: () => launchUrl(Uri.parse('mailto:contact@gentriwasa.example')),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Divider(color: Colors.white24),
              const SizedBox(height: 12),
              Text('© ${DateTime.now().year} GENTRI WASA. ${t('footer_rights')}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  /// Navigates by URL where a router is present, so footer links are
  /// shareable like every other page. [screen] remains the fallback for the
  /// non-routed builds that reuse this footer.
  void _push(BuildContext context, Widget screen, String path) {
    if (GoRouter.maybeOf(context) != null) {
      context.go(path);
      return;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
    Navigator.of(context).push(webPageRoute(screen));
  }
}

class _FooterLink extends StatefulWidget {
  const _FooterLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_FooterLink> createState() => _FooterLinkState();
}

class _FooterLinkState extends State<_FooterLink> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 150),
            style: TextStyle(color: _hovering ? Colors.white : Colors.white70, fontSize: 13),
            child: Text(widget.label),
          ),
        ),
      ),
    );
  }
}
