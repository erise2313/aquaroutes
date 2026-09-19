import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../constants/web_theme.dart';
import '../../web_router.dart';
import '../../widgets/web_footer.dart';
import '../../widgets/web_nav_bar.dart';
import '../../widgets/web_page_header.dart';
import '../../widgets/web_page_route.dart';
import 'account_deletion_screen.dart';
import 'contact_screen.dart';

/// The association's privacy policy, at `/privacy`.
///
/// Google Play requires a publicly reachable privacy policy for any app that
/// handles personal data, and this one handles names, phone numbers, delivery
/// coordinates and precise device location. The URL is also what goes in the
/// Play Console listing and must stay reachable for as long as the app is
/// published.
///
/// Every claim here is written from what the schema actually stores --
/// profiles, customer_addresses, orders, reviews, bulletin_comments -- and
/// from the services the code actually calls. Play cross-checks the listing's
/// Data Safety answers against this page, and a policy that promises less
/// than the app does is a rejection. If a column or a third-party call is
/// added later, this page is part of that change, not an afterthought.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  /// Last substantive revision. Play expects a policy that is evidently
  /// maintained, and reviewers do look at whether this moves.
  static const lastUpdated = '19 September 2026';

  void _openContact(BuildContext context) {
    if (GoRouter.maybeOf(context) != null) {
      context.go(WebRoutes.contact);
    } else {
      Navigator.push(context, webPageRoute(const ContactScreen()));
    }
  }

  void _openAccountDeletion(BuildContext context) {
    if (GoRouter.maybeOf(context) != null) {
      context.go(WebRoutes.accountDeletion);
    } else {
      Navigator.push(context, webPageRoute(const AccountDeletionScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = WebTheme.of(context);

    return Scaffold(
      backgroundColor: palette.paper,
      // No nav tab of its own; it's linked from the footer, beside the
      // account-deletion page it pairs with.
      appBar: const WebNavBar(currentPage: WebPage.faq),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const WebPageHeader(
              eyebrow: 'YOUR INFORMATION',
              title: 'Privacy Policy',
              subtitle:
                  'What the General Trias Water Station Association collects through GenTri: WASA, why it is collected, and who else can see it.',
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Updated(lastUpdated: lastUpdated),
                      const SizedBox(height: 28),

                      const _Body(
                        'This policy covers the GenTri: WASA mobile app and the association website, both operated by the General Trias Water Station Association. Browsing the bulletin board, the station directory and the map needs no account. Everything below applies once you create an account or place an order.',
                      ),

                      const _Heading('What we collect'),
                      const _Sub('Your account'),
                      const _Bullets([
                        'Your email address and password, held by our authentication provider. We never see your password.',
                        'Your full name and, if you give one, your phone number.',
                        'A profile photo, only if you upload one.',
                      ]),
                      const _Sub('Ordering'),
                      const _Bullets([
                        'Delivery addresses you save: a label you choose, its map coordinates, and any delivery notes you add.',
                        'Each order: what you ordered, the quantity and price, the payment method, the delivery location, and a contact number for that delivery.',
                        'If you order as a guest without an account, we still store the name and phone number you give so the station can complete the delivery.',
                      ]),
                      const _Sub('Location'),
                      const _Bullets([
                        'Your device location, when you allow it, to sort nearby stations and to place a delivery pin. You can refuse, and the app still works -- the list is simply not sorted by distance.',
                        'If you are a delivery driver on duty, your location is shared with the customer whose order you are carrying, so they can follow the delivery on a map. This happens only while you are on duty.',
                      ]),
                      const _Sub('What you post'),
                      const _Bullets([
                        'Station reviews and ratings, bulletin board posts, comments and reactions. These are visible to other users alongside your name.',
                      ]),

                      const _Heading('Why we collect it'),
                      const _Body(
                        'To deliver water you have ordered, to show you accredited stations near you, to let you follow a delivery, to let a station contact you about your order, and to run the association\'s accreditation and bulletin board. We do not use your information for advertising.',
                      ),

                      const _Heading('Who else can see it'),
                      const _Sub('People'),
                      const _Bullets([
                        'The water station you order from sees your name, contact number and delivery location for that order.',
                        'The driver assigned to your delivery sees the same details for that delivery only.',
                        'Association administrators can see account and station records in order to manage accreditation and handle deletion requests.',
                      ]),
                      const _Sub('Services we rely on'),
                      const _Body(
                        'Running the app means sending some information to the services below. We share only what each one needs to do its job.',
                      ),
                      const SizedBox(height: 12),
                      const _Bullets([
                        'Supabase -- stores the database, accounts and uploaded photos.',
                        'Firebase Hosting -- serves this website.',
                        'OpenStreetMap and MapTiler -- supply the map images. They receive which part of the map is being viewed.',
                        'OpenRouteService and the FOSSGIS routing service -- plan driving routes. They receive pickup and delivery coordinates so a road route can be calculated. They do not receive your name or contact details.',
                      ]),
                      const SizedBox(height: 16),
                      const _Callout(
                        'We do not sell your personal information, and we do not share it with advertisers.',
                      ),

                      const _Heading('How long we keep it'),
                      const _Body(
                        'Account details are kept while your account exists. Order records are kept afterwards for the association\'s own accounting and dispute handling, but with your name, phone number and exact address removed, so what remains cannot be traced back to you.',
                      ),

                      const _Heading('Deleting your account'),
                      const _Body(
                        'Customers can delete an account from within the app at any time, under My account. This removes your login, name, phone number, photo, reviews and comments, and it cannot be undone. Station owners, drivers and administrators send a deletion request instead, because those accounts are tied to association records that an administrator has to close first; you can withdraw that request until it is completed.',
                      ),
                      const SizedBox(height: 14),
                      _LinkRow(
                        label: 'Full instructions for deleting your account',
                        onTap: () => _openAccountDeletion(context),
                      ),

                      const _Heading('Your choices'),
                      const _Bullets([
                        'Location permission can be refused or withdrawn at any time in your device settings.',
                        'Your name and phone number can be corrected in the app under My account.',
                        'You can ask us what we hold about you, or ask us to correct it, using the contact details below.',
                      ]),

                      const _Heading('Children'),
                      const _Body(
                        'GenTri: WASA is intended for household and business water ordering and is not directed at children. We do not knowingly collect information from children under 13.',
                      ),

                      const _Heading('Changes to this policy'),
                      const _Body(
                        'If what we collect changes, this page changes with it and the date above is updated. Significant changes will be announced on the association bulletin board.',
                      ),

                      const _Heading('Contact'),
                      const _Body(
                        'For any question about this policy, or to make a request about your information, contact the General Trias Water Station Association.',
                      ),
                      const SizedBox(height: 14),
                      _LinkRow(
                        label: 'Association contact details',
                        onTap: () => _openContact(context),
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

class _Updated extends StatelessWidget {
  const _Updated({required this.lastUpdated});

  final String lastUpdated;

  @override
  Widget build(BuildContext context) {
    final palette = WebTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: palette.foam, borderRadius: BorderRadius.circular(8)),
      child: Text(
        'Last updated $lastUpdated',
        style: TextStyle(color: palette.inkMuted, fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 34, bottom: 10),
      child: Text(text, style: WebTheme.display(fontSize: 22)),
    );
  }
}

class _Sub extends StatelessWidget {
  const _Sub(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = WebTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 6),
      child: Text(
        text,
        style: TextStyle(color: palette.ink, fontSize: 15, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = WebTheme.of(context);
    return Text(text, style: TextStyle(color: palette.ink, fontSize: 15, height: 1.6));
  }
}

class _Bullets extends StatelessWidget {
  const _Bullets(this.items);

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final palette = WebTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8, right: 10),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(color: WebTheme.harborBlue, shape: BoxShape.circle),
                  ),
                ),
                Expanded(
                  child: Text(item, style: TextStyle(color: palette.ink, fontSize: 15, height: 1.55)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Callout extends StatelessWidget {
  const _Callout(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = WebTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.foam,
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: WebTheme.sealGold, width: 4)),
      ),
      child: Text(
        text,
        style: TextStyle(color: palette.ink, fontSize: 15, height: 1.5, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: WebTheme.harborBlue,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      ),
      icon: const Icon(Icons.arrow_forward, size: 16),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}
