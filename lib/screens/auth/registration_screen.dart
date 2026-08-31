import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math'; // Required for generating the invite/worker code

import '../../constants/web_theme.dart';
import '../../widgets/auth_text_field.dart';
import '../../widgets/fade_slide_in.dart';
import '../../widgets/hover_scale.dart';
import '../../widgets/wasa_shield_logo.dart';
import '../../widgets/web_page_route.dart';
import 'login_screen.dart';

/// Self-registration for the three roles that can sign themselves up:
/// station_owner, driver, and public_consumer (a resident/customer account).
/// Browsing the app and the Bulletin Board stay no-login by design, but
/// placing an order requires an account (see quick_order_screen.dart) --
/// this is where that account gets created. wasa_admin accounts are seeded
/// directly via SQL (0010_seed_gentri_wasa.sql or a manual insert), never
/// through this screen.

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  // Shared Controllers
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _fullNameController = TextEditingController();

  // Station Owner-Specific Controllers
  final _stationNameController = TextEditingController();
  final _stationAddressController = TextEditingController();

  // Driver-Specific Controllers
  final _inviteCodeController = TextEditingController();
  final _plateNumberController = TextEditingController();
  final _capacityController = TextEditingController();

  String _selectedRole = 'station_owner';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // If we got here already signed in (e.g. the "Finish Setting Up Your
    // Account" button on NoMembershipScreen, for an account whose role-RPC
    // failed after signUp() succeeded), prefill the email so the
    // isRetryOfSameAccount check below actually triggers without the user
    // having to remember and retype it themselves.
    final currentEmail = supabase.auth.currentSession?.user.email;
    if (currentEmail != null) {
      _emailController.text = currentEmail;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _fullNameController.dispose();
    _stationNameController.dispose();
    _stationAddressController.dispose();
    _inviteCodeController.dispose();
    _plateNumberController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  // Generates a random 6-character invite code for a new station.
  String _generateInviteCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = Random();
    return String.fromCharCodes(Iterable.generate(6, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
  }

  String? _requiredField(String? value, String label) {
    if (value == null || value.trim().isEmpty) return 'Enter $label';
    return null;
  }

  String? _validateEmail(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Enter your email address';
    if (!trimmed.contains('@') || !trimmed.contains('.')) return 'Enter a valid email address';
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Enter a password';
    if (value.length < 8) return 'Password must be at least 8 characters';
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (value != _passwordController.text) return 'Passwords do not match';
    return null;
  }

  Future<void> _signUp() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isLoading = true);

    try {
      // Create the base Authentication Account. The handle_new_auth_user
      // trigger (0001_core_identity.sql) creates the matching `profiles` row.
      // The driver path's invite-code validation now happens server-side
      // inside register_driver_for_station() (0005_workers.sql) instead of
      // a client-side pre-check, since that same RPC also has to run after
      // the auth session exists (it reads auth.uid()).
      //
      // If signUp() already succeeded on a previous attempt but the
      // role-linking RPC below then failed (e.g. a driver mistyped their
      // invite code), the account already exists and is already signed in
      // -- calling signUp() again for the same email would just fail with
      // "User already registered" and leave them stuck. Reuse the existing
      // session and retry only the RPC in that case -- but only when it's
      // for the SAME email being submitted now, otherwise a user who
      // changes the email field to try a different account entirely would
      // have the RPC silently applied to the old, still-signed-in identity.
      final currentSessionEmail = supabase.auth.currentSession?.user.email;
      final isRetryOfSameAccount = currentSessionEmail != null && currentSessionEmail == _emailController.text.trim();

      if (!isRetryOfSameAccount) {
        final res = await supabase.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          data: {'full_name': _fullNameController.text.trim()},
        );
        if (res.user == null) return;
      }

      if (_selectedRole == 'station_owner') {
        // Single RPC creates the water_stations row and the station_owner
        // membership atomically -- see register_station_owner()
        // (0003_memberships.sql). There is deliberately no client-insert
        // RLS policy on memberships, so a raw two-step insert here would
        // silently fail on the membership row (this was a real bug: station
        // owner registration didn't work at all before this RPC existed).
        //
        // _generateInviteCode() picks 6 random characters with no
        // uniqueness pre-check -- an extremely unlikely but real collision
        // against an existing station's invite_code would otherwise surface
        // as a raw "duplicate key" database error. Retry with a fresh code
        // a few times before giving up.
        for (var attempt = 0; ; attempt++) {
          try {
            await supabase.rpc('register_station_owner', params: {
              'p_station_name': _stationNameController.text.trim(),
              'p_station_address': _stationAddressController.text.trim(),
              'p_invite_code': _generateInviteCode(),
              // Placeholder coordinates until the owner sets their real
              // location via the location picker in their profile screen.
              'p_latitude': 14.3868,
              'p_longitude': 120.8817,
            });
            break;
          } on PostgrestException catch (e) {
            final isInviteCodeCollision = e.code == '23505' && (e.message.contains('invite_code'));
            if (!isInviteCodeCollision || attempt >= 4) rethrow;
          }
        }
      } else if (_selectedRole == 'driver') {
        // Single RPC creates the workers row, opens the first
        // worker_station_history entry, and inserts the driver membership
        // -- see register_driver_for_station() (0005_workers.sql). Raises
        // if the invite code doesn't match any station.
        await supabase.rpc('register_driver_for_station', params: {
          'p_invite_code': _inviteCodeController.text.trim(),
          'p_full_name': _fullNameController.text.trim(),
          'p_phone_number': null,
          'p_vehicle_plate': _plateNumberController.text.trim().toUpperCase(),
          'p_jug_capacity': int.tryParse(_capacityController.text.trim()),
        });
      } else {
        // Customer account -- just a membership row (role public_consumer,
        // no station). Same reasoning as the other two RPCs: there is no
        // client-insert RLS policy on memberships.
        await supabase.rpc('register_customer', params: {
          'p_full_name': _fullNameController.text.trim(),
        });
      }

      // AuthGate reacts to the resulting auth-state/membership change and
      // routes to the right portal -- but only once this screen (pushed on
      // top of AuthGate's route) pops back out of the way.
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Registration Error: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WebTheme.paper,
      appBar: AppBar(
        backgroundColor: WebTheme.paper,
        elevation: 0,
        iconTheme: const IconThemeData(color: WebTheme.inkNavy),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: FadeSlideIn(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: WasaShieldLogo(size: 56)),
                    const SizedBox(height: 20),
                    Text('JOIN THE ASSOCIATION', textAlign: TextAlign.center, style: WebTheme.eyebrow.copyWith(fontSize: 11)),
                    const SizedBox(height: 8),
                    Text(
                      "Create an Account",
                      textAlign: TextAlign.center,
                      style: WebTheme.display(fontSize: 26),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Join GenTri: WASA and manage deliveries instantly.",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 32),

                    _buildRoleDropdown(),
                    const SizedBox(height: 24),

                    if (_selectedRole == 'driver')
                      _buildDriverFields()
                    else if (_selectedRole == 'public_consumer')
                      _buildCustomerFields()
                    else
                      _buildStationOwnerFields(),

                    const SizedBox(height: 24),

                    AuthTextField(
                      controller: _emailController,
                      label: "Email Address",
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      validator: _validateEmail,
                      autofillHints: const [AutofillHints.email],
                    ),
                    const SizedBox(height: 16),
                    AuthTextField(
                      controller: _passwordController,
                      label: "Password",
                      icon: Icons.lock_outline,
                      isPassword: true,
                      textInputAction: TextInputAction.next,
                      validator: _validatePassword,
                      autofillHints: const [AutofillHints.newPassword],
                    ),
                    const SizedBox(height: 16),
                    AuthTextField(
                      controller: _confirmPasswordController,
                      label: "Confirm Password",
                      icon: Icons.lock_outline,
                      isPassword: true,
                      textInputAction: TextInputAction.done,
                      validator: _validateConfirmPassword,
                      onSubmitted: (_) => _signUp(),
                      autofillHints: const [AutofillHints.newPassword],
                    ),

                    const SizedBox(height: 32),

                    HoverScale(
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _signUp,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: WebTheme.harborBlue,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                "REGISTER",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    TextButton(
                      onPressed: () {
                        Navigator.pushReplacement(context, webPageRoute(const LoginScreen()));
                      },
                      child: RichText(
                        text: TextSpan(
                          text: "Already have an account? ",
                          style: TextStyle(color: Colors.grey.shade700),
                          children: [
                            TextSpan(text: "Login here", style: TextStyle(color: WebTheme.harborBlue, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedRole,
      decoration: InputDecoration(
        labelText: "Account Type",
        prefixIcon: const Icon(Icons.badge_outlined, color: WebTheme.harborBlue),
        filled: true,
        fillColor: WebTheme.foam,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: WebTheme.harborBlue, width: 2),
        ),
      ),
      items: const [
        DropdownMenuItem(value: 'station_owner', child: Text("Water Station Owner")),
        DropdownMenuItem(value: 'driver', child: Text("Driver / Helper")),
        DropdownMenuItem(value: 'public_consumer', child: Text("Resident / Customer Account")),
      ],
      onChanged: (String? newValue) {
        if (newValue != null) {
          setState(() => _selectedRole = newValue);
        }
      },
    );
  }

  Widget _buildStationOwnerFields() {
    return Column(
      children: [
        AuthTextField(
          controller: _stationNameController,
          label: "Water Station Name",
          icon: Icons.water_drop_outlined,
          textInputAction: TextInputAction.next,
          validator: (v) => _requiredField(v, 'your station name'),
        ),
        const SizedBox(height: 16),
        AuthTextField(
          controller: _fullNameController,
          label: "Owner Full Name",
          icon: Icons.person_outline,
          textInputAction: TextInputAction.next,
          validator: (v) => _requiredField(v, 'your full name'),
          autofillHints: const [AutofillHints.name],
        ),
        const SizedBox(height: 16),
        AuthTextField(
          controller: _stationAddressController,
          label: "Station Address (San Francisco, General Trias)",
          icon: Icons.store_mall_directory_outlined,
          textInputAction: TextInputAction.next,
          validator: (v) => _requiredField(v, 'your station address'),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: WebTheme.sealGold.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: WebTheme.sealGold.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: WebTheme.sealGold),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  "Business Permit / KYC upload will be required after successful registration.",
                  style: TextStyle(fontSize: 12, color: WebTheme.inkNavy),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCustomerFields() {
    return Column(
      children: [
        AuthTextField(
          controller: _fullNameController,
          label: "Full Name",
          icon: Icons.person_outline,
          textInputAction: TextInputAction.next,
          validator: (v) => _requiredField(v, 'your full name'),
          autofillHints: const [AutofillHints.name],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: WebTheme.foam,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: WebTheme.harborBlue),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  "Use this to place water orders and track your order history. Browsing the Bulletin Board and station map never requires an account.",
                  style: TextStyle(fontSize: 12, color: WebTheme.inkNavy),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDriverFields() {
    return Column(
      children: [
        AuthTextField(
          controller: _fullNameController,
          label: "Driver Full Name",
          icon: Icons.person_outline,
          textInputAction: TextInputAction.next,
          validator: (v) => _requiredField(v, 'your full name'),
          autofillHints: const [AutofillHints.name],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: WebTheme.foam,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              const Row(
                children: [
                  Icon(Icons.vpn_key, color: WebTheme.harborBlue),
                  SizedBox(width: 8),
                  Text("Station Link Key", style: TextStyle(fontWeight: FontWeight.bold, color: WebTheme.harborBlue)),
                ],
              ),
              const SizedBox(height: 8),
              AuthTextField(
                controller: _inviteCodeController,
                label: "Enter Station Invite Code",
                icon: Icons.numbers,
                textInputAction: TextInputAction.next,
                validator: (v) => _requiredField(v, 'the station invite code'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: AuthTextField(
                controller: _plateNumberController,
                label: "Plate No.",
                icon: Icons.directions_car,
                textInputAction: TextInputAction.next,
                validator: (v) => _requiredField(v, 'the vehicle plate number'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AuthTextField(
                controller: _capacityController,
                label: "Max Jugs",
                icon: Icons.scale,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                validator: (v) => _requiredField(v, 'the jug capacity'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
