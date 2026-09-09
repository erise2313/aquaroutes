import 'package:flutter/material.dart';

import 'about_info_screen.dart';
import 'contact_info_screen.dart';
import 'faq_info_screen.dart';
import 'for_station_owners_info_screen.dart';
import 'how_accreditation_works_info_screen.dart';
import 'jug_clearinghouse_info_screen.dart';

/// Menu into the six info pages that used to be website-only (About, FAQ,
/// Contact, For Station Owners, How Accreditation Works, Jug
/// Clearinghouse) -- all now shared, admin-editable content also readable
/// in the app (supabase/patch_website_content_cms.sql). One shared hub so
/// both entry points (public_home_screen.dart's app bar, station owners'
/// profile screen) only need to link to one place.
class AboutWasaHubScreen extends StatelessWidget {
  const AboutWasaHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final entries = <(IconData, String, String, WidgetBuilder)>[
      (Icons.info_outline, 'About WASA', 'What the association does, and the barangays it covers', (_) => const AboutInfoScreen()),
      (Icons.help_outline, 'FAQ', 'Common questions about ordering, pricing, and accreditation', (_) => const FaqInfoScreen()),
      (Icons.contact_mail_outlined, 'Contact', 'Association office details', (_) => const ContactInfoScreen()),
      (Icons.storefront_outlined, 'For Station Owners', 'Why join, and what you\'ll need', (_) => const ForStationOwnersInfoScreen()),
      (Icons.verified_outlined, 'How Accreditation Works', 'The full permit checklist and review process', (_) => const HowAccreditationWorksInfoScreen()),
      (Icons.swap_horiz, 'Jug Clearinghouse', 'How inter-station jug settlement works', (_) => const JugClearinghouseInfoScreen()),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('About WASA')),
      body: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: entries.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final (icon, title, subtitle, builder) = entries[index];
          return Card(
            child: ListTile(
              leading: Icon(icon, color: Colors.blue.shade700),
              title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(subtitle),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: builder)),
            ),
          );
        },
      ),
    );
  }
}
