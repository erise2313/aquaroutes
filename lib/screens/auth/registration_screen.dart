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
import '../app_route.dart';
import '../merchant/location_picker_screen.dart';
import '../web/privacy_policy_screen.dart';
import '../../utils/log.dart';
import '../../utils/error_text.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import '../../utils/jug_capacity.dart';
import '../../widgets/written_address_fields.dart';
import '../../utils/written_address.dart';
import '../../services/station_address.dart';
import 'package:aquaroute/constants/brand_tokens.dart';

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

  /// Agreement to the privacy notice. Unticked by default, as RA 10173
  /// expects consent to be an affirmative act.
  bool _consented = false;
  bool _showConsentError = false;

  // Shared Controllers
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _fullNameController = TextEditingController();

  // Station Owner-Specific Controllers
  final _stationNameController = TextEditingController();
  final _stationAddressController = TextEditingController();

  // The station's written address (house no./street, barangay, city,
  // landmark); _stationAddressController is no longer shown.
  final _stationStreetController = TextEditingController();
  final _stationCityController = TextEditingController();
  final _stationLandmarkController = TextEditingController();
  String? _stationBarangay;

  /// Where the station is, if the owner pinned it while registering. Without
  /// a pin the station is saved at a placeholder point in General Trias and
  /// the owner sets it later from their profile -- which many never did, so
  /// stations sat on the wrong spot on the public map.
  double? _stationLat;
  double? _stationLng;

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
    _stationStreetController.dispose();
    _stationCityController.dispose();
    _stationLandmarkController.dispose();
    _inviteCodeController.dispose();
    _plateNumberController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  // Generates a random 6-character invite code for a new station.
  String _generateInviteCode() {
    // No 0/O or 1/I: they look alike, and drivers type these codes in.
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
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
    final formOk = _formKey.currentState?.validate() ?? false;
    setState(() => _showConsentError = !_consented);
    if (!formOk || !_consented) return;

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

      // The retry is only for an account whose role was never linked. One
      // that already has a role is simply an existing account: treating it
      // as a retry let someone "register" an email already in use and land
      // on the home page (APP-173).
      if (isRetryOfSameAccount) {
        final existing = await supabase
            .from('memberships')
            .select('id')
            .eq('profile_id', supabase.auth.currentUser!.id)
            .limit(1);
        if (existing.isNotEmpty) {
          throw const AuthException('This email already has an account. Log in instead.');
        }
      }

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
            final stationId = await supabase.rpc('register_station_owner', params: {
              'p_station_name': _stationNameController.text.trim(),
              'p_station_address': formatWrittenAddress(
                street: _stationStreetController.text,
                barangay: _stationBarangay,
                city: _stationCityController.text,
              ),
              'p_invite_code': _generateInviteCode(),
              // The pinned location, or a placeholder until the owner sets
              // it from the location picker in their profile.
              'p_latitude': _stationLat ?? 14.3868,
              'p_longitude': _stationLng ?? 120.8817,
            });
            // The address parts and barangay, beside the one-line address
            // the registration function stores. Best effort: the station
            // exists either way, and the owner can finish it in Profile.
            if (stationId is String) {
              try {
                await supabase.from('water_stations').update(await stationAddressPayload(
                  supabase,
                  street: _stationStreetController.text,
                  barangay: _stationBarangay,
                  city: _stationCityController.text,
                  landmark: _stationLandmarkController.text,
                )).eq('id', stationId);
              } catch (e) {
                logError('save station address parts', e);
              }
            }
            break;
          } on PostgrestException catch (e) {
            final isInviteCodeCollision = e.code == '23505' && (e.message.contains('invite_code'));
            if (!isInviteCodeCollision || attempt >= 4) rethrow;
          }
        }
      } else if (_selectedRole == 'station_staff') {
        // Counter / dispatch staff join with the station's STAFF code, which
        // the owner issues from Team -- a different code from the drivers',
        // so a driver code can't make someone staff or the reverse. See
        // register_staff_for_station() (patch_roles_governance.sql).
        await supabase.rpc('register_staff_for_station', params: {
          'p_staff_code': _inviteCodeController.text.trim(),
          'p_full_name': _fullNameController.text.trim(),
          'p_phone_number': null,
        });
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

      // Recorded once the account exists. Not allowed to block a sign-up that
      // has otherwise succeeded: the box was ticked, and a project that
      // hasn't had patch_overhaul_gaps.sql run yet has no such function.
      try {
        await supabase.rpc('record_privacy_consent', params: {'p_version': PrivacyPolicyScreen.lastUpdated});
      } catch (e) {
        logError('record privacy consent', e);
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
            content: Text(describeError(e)),
            backgroundColor: BrandStatus.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      // The ambient theme, not WebTheme: pushed from the app, appRoute wraps
      // this in AppTheme, which registers AppPalette -- so WebTheme.of fell
      // back to its light palette and painted a white page under the app's
      // dark mode, with near-white text on it.
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        iconTheme: IconThemeData(color: scheme.onSurface),
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
                    Text('JOIN THE ASSOCIATION', textAlign: TextAlign.center, style: WebTheme.eyebrowFor(context)),
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
                      style: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 32),

                    _buildRoleDropdown(),
                    const SizedBox(height: 24),

                    if (_selectedRole == 'driver')
                      _buildDriverFields()
                    else if (_selectedRole == 'station_staff')
                      _buildStaffFields()
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

                    const SizedBox(height: 20),
                    _ConsentCheckbox(
                      value: _consented,
                      showError: _showConsentError,
                      onChanged: (v) => setState(() {
                        _consented = v;
                        if (v) _showConsentError = false;
                      }),
                    ),

                    const SizedBox(height: 24),

                    HoverScale(
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _signUp,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: scheme.primary,
                          foregroundColor: scheme.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: _isLoading
                            ? SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: scheme.onPrimary,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                "Create account",
                                style: TextStyle(
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
                          style: TextStyle(color: scheme.onSurfaceVariant),
                          children: [
                            TextSpan(text: "Login here", style: TextStyle(color: scheme.primary, fontWeight: FontWeight.bold)),
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
    final scheme = Theme.of(context).colorScheme;

    return DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: _selectedRole,
      decoration: InputDecoration(
        labelText: "Account type",
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        prefixIcon: Icon(Icons.badge_outlined, color: scheme.primary),
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
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
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      // Customers and drivers use the mobile app only, so the website
      // offers just the station accounts.
      items: [
        const DropdownMenuItem(value: 'station_owner', child: Text("Water Station Owner")),
        if (!kIsWeb) const DropdownMenuItem(value: 'driver', child: Text("Driver / Helper")),
        const DropdownMenuItem(value: 'station_staff', child: Text("Station Staff (counter / dispatch)")),
        if (!kIsWeb) const DropdownMenuItem(value: 'public_consumer', child: Text("Resident / Customer Account")),
      ],
      onChanged: (String? newValue) {
        if (newValue != null) {
          setState(() => _selectedRole = newValue);
        }
      },
    );
  }

  Future<void> _pickStationLocation() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      ambientRoute(
        context,
        LocationPickerScreen(
          initialLatitude: _stationLat,
          initialLongitude: _stationLng,
          initialStationName: _stationNameController.text.trim(),
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _stationLat = (result['latitude'] as num).toDouble();
      _stationLng = (result['longitude'] as num).toDouble();
      final name = (result['station_name'] as String?)?.trim();
      if (name != null && name.isNotEmpty && _stationNameController.text.trim().isEmpty) {
        _stationNameController.text = name;
      }
    });
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
        WrittenAddressFields(
          street: _stationStreetController,
          city: _stationCityController,
          landmark: _stationLandmarkController,
          barangay: _stationBarangay,
          onBarangayChanged: (v) => setState(() => _stationBarangay = v),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _pickStationLocation,
            icon: Icon(_stationLat == null ? Icons.add_location_alt_outlined : Icons.check_circle_outline),
            label: Text(_stationLat == null ? 'Pin your station on the map' : 'Location pinned -- change'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, left: 4),
          child: Text(
            _stationLat == null
                ? 'Optional now; you can also set it later from your profile.'
                : 'Pinned at ${_stationLat!.toStringAsFixed(5)}, ${_stationLng!.toStringAsFixed(5)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
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
              Expanded(
                child: Text(
                  "Business Permit / KYC upload will be required after successful registration.",
                  style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurface),
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
        Builder(builder: (context) {
          // Ambient scheme, not WebTheme: under AppTheme this resolved to the
          // light palette, so the box stayed pale in the app's dark mode with
          // near-white text inside it.
          final scheme = Theme.of(context).colorScheme;
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Use this to place water orders and track your order history. Browsing the Bulletin Board and station map never requires an account.",
                    style: TextStyle(fontSize: 16, color: scheme.onSurface),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  /// Staff need only their name and the station's staff code.
  Widget _buildStaffFields() {
    return Column(
      children: [
        AuthTextField(
          controller: _fullNameController,
          label: "Your Full Name",
          icon: Icons.person_outline,
          textInputAction: TextInputAction.next,
          validator: (v) => _requiredField(v, 'your full name'),
          autofillHints: const [AutofillHints.name],
        ),
        const SizedBox(height: 16),
        AuthTextField(
          controller: _inviteCodeController,
          label: "Station Staff Code",
          icon: Icons.vpn_key,
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.characters,
          validator: (v) => _requiredField(v, 'the staff code from the station owner'),
        ),
        const SizedBox(height: 8),
        Builder(
          builder: (context) => Text(
            'Ask the station owner for the staff code (Team page). It is not the driver code.',
            style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
        Builder(builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.vpn_key, color: scheme.primary),
                  const SizedBox(width: 8),
                  Text("Station Link Key", style: TextStyle(fontWeight: FontWeight.bold, color: scheme.primary)),
                ],
              ),
              const SizedBox(height: 8),
              AuthTextField(
                controller: _inviteCodeController,
                label: "Enter Station Invite Code",
                icon: Icons.numbers,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.characters,
                validator: (v) => _requiredField(v, 'the station invite code'),
              ),
            ],
          ),
          );
        }),
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
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                helperText: '1 to $kMaxJugCapacity',
                validator: jugCapacityError,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// "I have read and agree to the Privacy Policy", with the policy one tap
/// away. The whole row toggles the box, so the target is the full width
/// rather than an 18px square.
class _ConsentCheckbox extends StatelessWidget {
  const _ConsentCheckbox({required this.value, required this.showError, required this.onChanged});

  final bool value;
  final bool showError;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => onChanged(!value),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: value,
                  onChanged: (v) => onChanged(v ?? false),
                  isError: showError,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'I have read the Privacy Policy and agree to GenTri WASA collecting and using my information as it describes.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 44),
          child: TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => Theme(
                  data: Theme.of(context).brightness == Brightness.dark ? WebTheme.dark : WebTheme.light,
                  child: const PrivacyPolicyScreen(standalone: true),
                ),
              ),
            ),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Read the Privacy Policy'),
          ),
        ),
        if (showError)
          Padding(
            padding: const EdgeInsets.only(left: 52, top: 2),
            child: Text(
              'Tick the box to agree before creating your account.',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error, fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );
  }
}
