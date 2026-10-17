import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../account_settings_section.dart';

/// The account menu in both portals' sidebar footer: account settings and
/// password, an optional way back to the public website, and sign out.
///
/// Admin had one; the station-owner portal had none, so an owner on the web
/// had to find "sign out" at the bottom of the Profile page. The test cases
/// sign out "from the profile menu" (GTW-WEB-085), as on the public site.
class PortalAccountMenu extends StatelessWidget {
  const PortalAccountMenu({super.key, this.onLeavePortal});

  /// Shown as "Back to the website" when set -- the public site's portal.
  final VoidCallback? onLeavePortal;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Account',
      icon: const Icon(Icons.account_circle_outlined),
      onSelected: (value) {
        switch (value) {
          case 'account':
            showDialog(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('Account'),
                contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
                content: const SizedBox(width: 420, child: AccountSettingsSection()),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
                ],
              ),
            );
          case 'leave':
            onLeavePortal?.call();
          case 'signout':
            Supabase.instance.client.auth.signOut();
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'account',
          child: ListTile(leading: Icon(Icons.manage_accounts_outlined), title: Text('Account & password')),
        ),
        if (onLeavePortal != null)
          const PopupMenuItem(
            value: 'leave',
            child: ListTile(leading: Icon(Icons.public), title: Text('Back to the website')),
          ),
        const PopupMenuItem(
          value: 'signout',
          child: ListTile(leading: Icon(Icons.logout), title: Text('Sign Out')),
        ),
      ],
    );
  }
}
