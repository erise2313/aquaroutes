import 'package:flutter/material.dart';

import '../../../constants/app_colors.dart';
import '../../../widgets/portal/portal.dart';
import '../../app_route.dart';
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
      body: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          final density = PortalDensity.of(context);

          return ListView.separated(
            padding: density.pagePadding,
            itemCount: entries.length,
            separatorBuilder: (context, index) => SizedBox(height: density.gap),
            itemBuilder: (context, index) {
              final (icon, title, subtitle, builder) = entries[index];
              return PortalCard(
                accent: AppColors.primary,
                // The destination comes from `entries` as a WidgetBuilder, so
                // it's built here and handed to appRoute like any other screen.
                onTap: () => Navigator.push(context, appRoute(Builder(builder: builder))),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: StatusTint.surface(context, AppColors.primary),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: StatusTint.onTint(context, AppColors.primary), size: 21),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: theme.textTheme.titleMedium),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
