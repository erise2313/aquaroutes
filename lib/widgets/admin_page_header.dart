import 'package:flutter/material.dart';

import 'portal/portal_page_header.dart';

/// The header on an admin page.
///
/// It used to be a navy band with a gold rule, drawn on every admin page.
/// Against the app's light, paper-coloured screens that band was the most
/// visible reason the portal read as a different product, so it now renders
/// the same [PortalPageHeader] the station-owner portal and the app use. The
/// constructor is unchanged, so no admin screen had to change to adopt it.
///
/// The theme toggle, notifications and account menu live in the portal's
/// sidebar (widgets/portal/portal_sidebar_shell.dart), the same three
/// controls on every page; page-specific [actions] such as Export still
/// belong here. A pushed page gets a back button.
class AdminPageHeader extends StatelessWidget {
  const AdminPageHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.actions = const [],
    this.bottom,
    @Deprecated('The shell carries the account controls now; this has no effect.') this.showSignOut = false,
  });

  final String title;

  /// Small caps above the title -- which part of the portal this page
  /// belongs to.
  final String? eyebrow;

  final String? subtitle;
  final List<Widget> actions;
  final Widget? bottom;

  final bool showSignOut;

  @override
  Widget build(BuildContext context) {
    return PortalPageHeader(
      title: title,
      eyebrow: eyebrow,
      subtitle: subtitle,
      actions: actions,
      bottom: bottom,
    );
  }
}
