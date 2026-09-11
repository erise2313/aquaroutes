import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../constants/web_theme.dart';
import '../../web_router.dart';
import '../../widgets/web_footer.dart';
import '../../widgets/web_nav_bar.dart';
import '../../widgets/web_page_header.dart';
import '../../widgets/web_page_route.dart';
import 'contact_screen.dart';

/// How to delete a GenTri WASA account, at `/account-deletion`.
///
/// Google Play asks apps with sign-up for a web page explaining account
/// deletion, reachable without the app. The steps here mirror the app:
/// customers delete their own account (widgets/account_settings_section.dart);
/// station owners, drivers and admins send a request WASA admin completes
/// (supabase/functions/delete-account).
class AccountDeletionScreen extends StatelessWidget {
  const AccountDeletionScreen({super.key});

  void _openContact(BuildContext context) {
    if (GoRouter.maybeOf(context) != null) {
      context.go(WebRoutes.contact);
    } else {
      Navigator.push(context, webPageRoute(const ContactScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = WebTheme.of(context);
    return Scaffold(
      backgroundColor: palette.paper,
      // No nav tab of its own; it's linked from the footer, next to the FAQ.
      appBar: const WebNavBar(currentPage: WebPage.faq),
      body: SingleChildScrollView(
        child: Column(
          children: [
            WebPageHeader(
              eyebrow: 'YOUR DATA',
              title: 'Deleting your account',
              subtitle: 'How to delete a GenTri: WASA account, and what happens to your information.',
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Section(
                        icon: Icons.person_outline,
                        title: 'Customers',
                        paragraphs: const [
                          'In the app, open My Account (top right), choose Delete account, and type DELETE to confirm. '
                              'It happens immediately.',
                          'If an order is still on its way, wait for it to arrive or cancel it first.',
                        ],
                      ),
                      _Section(
                        icon: Icons.storefront_outlined,
                        title: 'Station owners, drivers and WASA staff',
                        paragraphs: const [
                          'Your account is linked to association records, so WASA admin completes the deletion. '
                              'In the app or on this website, open your Profile and choose Request account deletion.',
                          'A station owner\'s station is closed first. You can withdraw the request until it is done.',
                        ],
                      ),
                      _Section(
                        icon: Icons.delete_outline,
                        title: 'What is deleted, and what is kept',
                        paragraphs: const [
                          'Deleted: your login, name, phone number, profile photo, reviews, comments and reactions.',
                          'Kept without your name: the items and amounts of past orders (stations need them for '
                              'their records, and the delivery address is reduced to a rough area), and association '
                              'records such as the jug ledger and permit reviews. Posts you made are shown as '
                              '"Former member", without their photo.',
                        ],
                      ),
                      _Section(
                        icon: Icons.mail_outline,
                        title: "Can't use the app?",
                        paragraphs: const [
                          'Contact WASA from the email address on your account and ask for it to be deleted.',
                        ],
                        action: FilledButton.icon(
                          onPressed: () => _openContact(context),
                          icon: const Icon(Icons.arrow_forward),
                          label: const Text('Contact WASA'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const WebFooter(),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.title, required this.paragraphs, this.action});

  final IconData icon;
  final String title;
  final List<String> paragraphs;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = WebTheme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: palette.foam, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: WebTheme.harborBlue),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: WebTheme.display(fontSize: 20))),
            ],
          ),
          const SizedBox(height: 10),
          for (final p in paragraphs)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(p, style: TextStyle(color: palette.ink, height: 1.5)),
            ),
          if (action != null) ...[const SizedBox(height: 8), action!],
        ],
      ),
    );
  }
}
