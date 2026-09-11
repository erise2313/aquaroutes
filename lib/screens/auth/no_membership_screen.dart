import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'login_screen.dart';
import 'registration_screen.dart';

/// Shown when a signed-in account has no active membership row 
/// no-login by design). There is deliberately no "customer" role to route to
class NoMembershipScreen extends StatelessWidget {
  const NoMembershipScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              // The old copy said ordering needs no account; it has required a
              // customer account since ordering moved behind sign-in.
              Text(
                'This account isn\'t linked to a GENTRI WASA station or role yet.\n\n'
                'To order water, finish setting up a customer account below. '
                'If you\'re a station owner or driver awaiting setup, contact WASA.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const RegistrationScreen())),
                child: const Text('Finish Setting Up Your Account'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () async {
                  await Supabase.instance.client.auth.signOut();
                  if (context.mounted) {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (context) => const LoginScreen()),
                      (route) => false,
                    );
                  }
                },
                child: const Text('Sign Out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
