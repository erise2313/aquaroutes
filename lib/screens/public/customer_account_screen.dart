import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../providers/app_state.dart';
import '../../widgets/account_settings_section.dart';
import '../../widgets/error_state.dart';
import '../../widgets/portal/portal.dart';
import 'addresses_screen.dart';
import 'my_orders_screen.dart';
import '../app_route.dart';
import '../../utils/error_text.dart';

/// Account screen for a signed-in customer (public_consumer membership) --
/// reachable from PublicHomeScreen's app bar once authenticated. Just a
/// profile editor + My Orders entry point + sign out; there's no separate
/// portal shell for public_consumer since browsing stays on PublicHomeScreen
/// itself (see auth_gate.dart).
class CustomerAccountScreen extends ConsumerStatefulWidget {
  const CustomerAccountScreen({super.key});

  @override
  ConsumerState<CustomerAccountScreen> createState() => _CustomerAccountScreenState();
}

class _CustomerAccountScreenState extends ConsumerState<CustomerAccountScreen> {
  final _supabase = Supabase.instance.client;
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final userId = _supabase.auth.currentUser!.id;
      final row = await _supabase.from('profiles').select('full_name, phone_number').eq('id', userId).maybeSingle();
      if (mounted) {
        setState(() {
          _fullNameController.text = row?['full_name'] as String? ?? '';
          _phoneController.text = row?['phone_number'] as String? ?? '';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load your account. ${describeError(e)}';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await ref.read(authServiceProvider).updateProfile(
            fullName: _fullNameController.text.trim(),
            phoneNumber: _phoneController.text.trim(),
          );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _signOut() async {
    await _supabase.auth.signOut();
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Widget _navCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required PortalDensity density,
    bool last = false,
  }) {
    final theme = Theme.of(context);

    return PortalCard(
      onTap: onTap,
      margin: EdgeInsets.only(bottom: last ? 0 : density.gap),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My account')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? ErrorState(message: _error!, onRetry: _load)
          : Builder(
              builder: (context) {
                final theme = Theme.of(context);
                final density = PortalDensity.of(context);

                return ListView(
                  padding: density.pagePadding,
                  children: [
                    PortalSection(
                      title: 'Your details',
                      subtitle: 'What a station sees when you place an order',
                      child: PortalCard(
                        lift: false,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _fullNameController,
                              decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline)),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(labelText: 'Phone number', prefixIcon: Icon(Icons.phone_outlined)),
                            ),
                            const SizedBox(height: 16),
                            PortalActionRow(
                              children: [
                                FilledButton(
                                  onPressed: _isSaving ? null : _save,
                                  child: _isSaving
                                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                      : const Text('Save changes'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: density.sectionGap),
                    PortalSection(
                      title: 'Ordering',
                      child: Column(
                        children: [
                          _navCard(
                            icon: Icons.place_outlined,
                            title: 'Delivery addresses',
                            subtitle: 'Save home and work so ordering is one tap',
                            onTap: () => Navigator.push(context, appRoute(const AddressesScreen())),
                            density: density,
                          ),
                          _navCard(
                            icon: Icons.receipt_long_outlined,
                            title: 'My orders',
                            subtitle: 'Past deliveries, and anything on its way',
                            onTap: () => Navigator.push(context, appRoute(const MyOrdersScreen())),
                            density: density,
                            last: true,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: density.sectionGap),
                    PortalSection(
                      title: 'Account',
                      child: Column(
                        children: [
                          PortalCard(
                            lift: false,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            margin: EdgeInsets.only(bottom: density.gap),
                            child: const AccountSettingsSection(),
                          ),
                          OutlinedButton.icon(
                            onPressed: _signOut,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: theme.colorScheme.error,
                              side: BorderSide(color: theme.colorScheme.error, width: 1.5),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            icon: const Icon(Icons.logout),
                            label: const Text('Sign out'),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
