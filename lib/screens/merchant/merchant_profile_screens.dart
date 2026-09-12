import 'package:aquaroute/screens/merchant/location_picker_screen.dart';
import 'package:aquaroute/screens/merchant/permit_vault_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/photo_service.dart';
import '../../services/supabase_service.dart';
import '../public/info/about_wasa_hub_screen.dart';
import '../app_route.dart';
import 'products_screen.dart';
import '../../constants/app_colors.dart';
import '../../widgets/account_settings_section.dart';
import '../../widgets/app_theme_toggle.dart';
import '../../widgets/portal/portal.dart';
import '../../utils/error_text.dart';

/// Builds the `profiles` table update payload (trimmed). Split from
/// [buildStationPayload] since profile identity and station business data
/// now live in separate tables (profiles vs. water_stations).
Map<String, dynamic> buildProfilePayload({required String fullName, required String phoneNumber}) {
  return {
    'full_name': fullName.trim(),
    'phone_number': phoneNumber.trim(),
  };
}

/// Builds the `water_stations` table update payload (trimmed).
Map<String, dynamic> buildStationPayload({required String stationName, required String stationAddress}) {
  return {
    'station_name': stationName.trim(),
    'station_address': stationAddress.trim(),
  };
}

class MerchantProfileScreen extends StatefulWidget {
  const MerchantProfileScreen({super.key});

  @override
  State<MerchantProfileScreen> createState() => _MerchantProfileScreenState();
}

class _MerchantProfileScreenState extends State<MerchantProfileScreen> {
  final supabase = Supabase.instance.client;
  final _photoService = PhotoService(SupabaseService.instance);

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isLoggingOut = false;
  bool _isUploadingAvatar = false;
  bool _isUploadingStationPhoto = false;
  String? _stationId;
  String? _avatarUrl;
  String? _stationPhotoUrl;
  Map<String, dynamic>? _profileData;
  Map<String, dynamic>? _stationData;
  bool _isAcceptingOrders = true;
  bool _offersJugExchange = false;
  final Set<int> _operatingDays = {1, 2, 3, 4, 5, 6, 7};
  TimeOfDay? _opensAt;
  TimeOfDay? _closesAt;

  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _stationNameController = TextEditingController();
  final TextEditingController _stationAddressController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _latitudeController = TextEditingController();
  final TextEditingController _longitudeController = TextEditingController();

  int _selectedTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _fetchProfileData();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _stationNameController.dispose();
    _stationAddressController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    setState(() => _isLoggingOut = true);

    try {
      await supabase.auth.signOut();
    } catch (e) {
      debugPrint("Logout error. ${describeError(e)}");
    } finally {
      if (mounted) {
        setState(() => _isLoggingOut = false);
        // AuthGate (the app's root widget) reacts to the resulting
        // auth-state change and shows LoginScreen itself -- just pop back
        // to reveal it, don't push a new LoginScreen route on top of it.
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  TimeOfDay? _timeOfDayFromString(String? time) {
    if (time == null) return null;
    final parts = time.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  String? _timeOfDayToString(TimeOfDay? time) {
    if (time == null) return null;
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00';
  }

  Future<void> _fetchProfileData() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw Exception("User not authenticated");

      final profile = await supabase.from('profiles').select().eq('id', userId).maybeSingle();
      final station = await supabase.from('water_stations').select().eq('owner_profile_id', userId).maybeSingle();

      if (mounted) {
        setState(() {
          _profileData = profile;
          _stationData = station;
          _stationId = station?['id'] as String?;
          _avatarUrl = profile?['avatar_url'] as String?;
          _stationPhotoUrl = station?['photo_url'] as String?;
          _fullNameController.text = (profile?['full_name'] as String?) ?? '';
          _phoneController.text = (profile?['phone_number'] as String?) ?? '';
          _stationNameController.text = (station?['station_name'] as String?) ?? '';
          _stationAddressController.text = (station?['station_address'] as String?) ?? '';
          _emailController.text = supabase.auth.currentUser?.email ?? '';
          _latitudeController.text = (station?['latitude'] as num?)?.toString() ?? '';
          _longitudeController.text = (station?['longitude'] as num?)?.toString() ?? '';
          _isAcceptingOrders = station?['accepts_new_orders'] as bool? ?? true;
          _offersJugExchange = station?['offers_jug_exchange'] as bool? ?? false;
          final operatingDaysRaw = station?['operating_days'] as List?;
          _operatingDays
            ..clear()
            ..addAll(operatingDaysRaw != null ? operatingDaysRaw.map((d) => (d as num).toInt()) : const [1, 2, 3, 4, 5, 6, 7]);
          _opensAt = _timeOfDayFromString(station?['opens_at'] as String?);
          _closesAt = _timeOfDayFromString(station?['closes_at'] as String?);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching profile. ${describeError(e)}");
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Failed to load profile data"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _openLocationPicker() async {
    final result = await Navigator.push(
      context,
      appRoute(LocationPickerScreen(
          initialLatitude: double.tryParse(_latitudeController.text) ?? 14.3868,
          initialLongitude: double.tryParse(_longitudeController.text) ?? 120.8817,
          initialStationName: _stationNameController.text,
        ),
      ),
    );

    if (result != null && result is Map<String, dynamic>) {
      setState(() {
        _latitudeController.text = result['latitude'].toString();
        _longitudeController.text = result['longitude'].toString();
        _stationNameController.text = result['station_name'];
      });
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final picked = result?.files.single;
    if (picked == null || picked.bytes == null) return;

    final extension = picked.extension ?? 'jpg';

    setState(() => _isUploadingAvatar = true);
    try {
      final url = await _photoService.uploadAvatar(profileId: userId, bytes: picked.bytes!, fileExtension: extension);
      await supabase.from('profiles').update({'avatar_url': url, 'updated_at': DateTime.now().toIso8601String()}).eq('id', userId);
      if (mounted) setState(() => _avatarUrl = url);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Photo upload failed. ${describeError(e)}')));
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  Future<void> _pickAndUploadStationPhoto() async {
    if (_stationId == null) return;

    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final picked = result?.files.single;
    if (picked == null || picked.bytes == null) return;

    final extension = picked.extension ?? 'jpg';

    setState(() => _isUploadingStationPhoto = true);
    try {
      final url = await _photoService.uploadStationPhoto(stationId: _stationId!, bytes: picked.bytes!, fileExtension: extension);
      await supabase.from('water_stations').update({'photo_url': url}).eq('id', _stationId!);
      if (mounted) setState(() => _stationPhotoUrl = url);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Photo upload failed. ${describeError(e)}')));
    } finally {
      if (mounted) setState(() => _isUploadingStationPhoto = false);
    }
  }

  Future<void> _saveProfile() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null || _stationId == null) return;

    setState(() => _isSaving = true);

    try {
      await supabase.from('profiles').update({
        ...buildProfilePayload(fullName: _fullNameController.text, phoneNumber: _phoneController.text),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);

      final stationPayload = buildStationPayload(
        stationName: _stationNameController.text,
        stationAddress: _stationAddressController.text,
      );

      final lat = double.tryParse(_latitudeController.text);
      final lng = double.tryParse(_longitudeController.text);
      if (lat != null && lng != null) {
        stationPayload['latitude'] = lat;
        stationPayload['longitude'] = lng;
      }
      stationPayload['accepts_new_orders'] = _isAcceptingOrders;
      // Water types and containers are no longer saved from here: they're
      // derived from the station's products (Products tab), and writing this
      // screen's copy back would overwrite them with whatever was loaded.
      stationPayload['offers_jug_exchange'] = _offersJugExchange;
      // All 7 days selected is treated as "no restriction" (same as never
      // having set a schedule) rather than storing a literal every-day
      // array -- keeps the common case simple for isOpenNow to interpret.
      stationPayload['operating_days'] = _operatingDays.length == 7 ? null : _operatingDays.toList();
      stationPayload['opens_at'] = _timeOfDayToString(_opensAt);
      stationPayload['closes_at'] = _timeOfDayToString(_closesAt);

      await supabase.from('water_stations').update(stationPayload).eq('id', _stationId!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile and station details updated successfully!')),
        );
      }
      await _fetchProfileData();
    } catch (e) {
      debugPrint('Failed to update profile: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update profile. ${describeError(e)}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const PortalPageHeader(
            eyebrow: 'Your station',
            title: 'Station Profile',
            subtitle: 'Who you are, what customers see, and where to find you',
            showBack: false,
            actions: [AppThemeToggle()],
          ),
          Expanded(
            child: _isLoading ? const Center(child: CircularProgressIndicator()) : _buildProfileContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileContent() {
    final density = PortalDensity.of(context);
    final bool isAccredited = _stationData?['is_accredited'] as bool? ?? false;

    // Everything scrolls now. The resources, account and logout controls used
    // to sit outside the scroll view in a fixed column, so at large system
    // text they had nowhere to go and squeezed the forms above them.
    return ListView(
      padding: density.pagePadding,
      children: [
        _buildIdentityHero(),
        SizedBox(height: density.sectionGap),
        _buildAccreditationBanner(isAccredited),
        SizedBox(height: density.sectionGap),
        PortalSection(
          title: 'Station details',
          subtitle: 'What customers see about you and how you take orders',
          child: _buildDetailTabs(density),
        ),
        SizedBox(height: density.sectionGap),
        PortalSection(
          title: 'Account',
          child: Column(
            children: [
              PortalCard(
                onTap: () => Navigator.push(context, appRoute(const AboutWasaHubScreen())),
                accent: AppColors.seal,
                margin: EdgeInsets.only(bottom: density.gap),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: StatusTint.onTint(context, AppColors.seal)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text('WASA Resources', style: Theme.of(context).textTheme.titleMedium),
                    ),
                    Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ],
                ),
              ),
              PortalCard(
                lift: false,
                padding: const EdgeInsets.symmetric(vertical: 8),
                margin: EdgeInsets.only(bottom: density.gap),
                child: const AccountSettingsSection(),
              ),
              OutlinedButton.icon(
                onPressed: _isLoggingOut ? null : _logout,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                  side: BorderSide(color: Theme.of(context).colorScheme.error, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: _isLoggingOut
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Theme.of(context).colorScheme.error,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.logout),
                label: const Text('Sign out', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.6)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The station's identity, on the brand gradient the public site uses for
  /// its hero. Was a flat Colors.blue.shade600 block that stayed the same
  /// bright blue in dark mode.
  Widget _buildIdentityHero() {
    final String ownerName = _profileData?['full_name'] ?? 'Unknown Owner';
    final String stationName = _stationData?['station_name'] ?? 'Unnamed Station';
    final String email = supabase.auth.currentUser?.email ?? '';

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.accent],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: _isUploadingAvatar ? null : _pickAndUploadAvatar,
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.white,
                  backgroundImage: _avatarUrl != null ? NetworkImage(_avatarUrl!) : null,
                  child: _isUploadingAvatar
                      ? const CircularProgressIndicator()
                      : (_avatarUrl == null ? const Icon(Icons.storefront, size: 34, color: AppColors.primary) : null),
                ),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                  child: const Icon(Icons.camera_alt, size: 12, color: Colors.white),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // White on the gradient in both modes: the band is dark
                // either way, so this is one of the few places a fixed
                // foreground colour is the correct answer.
                Text(
                  ownerName,
                  style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  '$stationName\n$email',
                  style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The three forms, with the selected one rendered directly beneath the
  /// tabs.
  ///
  /// This was a TabBarView, which demands a bounded height inside a scrolling
  /// column -- the height was a hand-tuned 380px multiplied by the text scale,
  /// which clipped long forms at some sizes and left dead space at others.
  /// Showing one form at a time needs no height at all.
  Widget _buildDetailTabs(PortalDensity density) {
    final scheme = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: 3,
      initialIndex: _selectedTabIndex,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A TabBar's height is fixed, so its labels clip past about 130%
          // system text. The forms below it scale freely.
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: TabBar(
              onTap: (index) => setState(() => _selectedTabIndex = index),
              labelColor: scheme.primary,
              unselectedLabelColor: scheme.onSurfaceVariant,
              indicatorColor: scheme.primary,
              tabs: const [
                Tab(text: 'Profile'),
                Tab(text: 'Station Info'),
                Tab(text: 'Location'),
              ],
            ),
          ),
          SizedBox(height: density.gap),
          switch (_selectedTabIndex) {
            1 => _buildEditableStationForm(),
            2 => _buildLocationForm(),
            _ => _buildEditableProfileForm(),
          },
        ],
      ),
    );
  }

  Widget _buildAccreditationBanner(bool isAccredited) {
    final theme = Theme.of(context);

    if (isAccredited) {
      return const StatusCallout(
        accent: AppColors.cleared,
        icon: Icons.verified,
        title: 'WASA Accredited. Your station is visible to the public.',
      );
    }

    return PortalCard(
      lift: false,
      accent: AppColors.pendingClearance,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: StatusTint.onTint(context, AppColors.pendingClearance),
                size: 26,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text('Action required', style: theme.textTheme.titleMedium)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "Your station isn't accredited yet. Upload your permits so WASA can review them.",
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          PortalActionRow(
            children: [
              FilledButton.icon(
                onPressed: () => Navigator.push(context, appRoute(const PermitVaultScreen())),
                icon: const Icon(Icons.upload_file),
                label: const Text('Open Permit Vault'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The save control every form ends with.
  Widget _buildSaveButton({String label = 'Save changes'}) {
    return PortalActionRow(
      children: [
        FilledButton.icon(
          onPressed: _isSaving ? null : _saveProfile,
          icon: _isSaving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save),
          label: Text(_isSaving ? 'Saving...' : label),
        ),
      ],
    );
  }

  Widget _buildEditableProfileForm() {
    return PortalCard(
      lift: false,
      child: Column(
        children: [
          _buildInputField(
            controller: _fullNameController,
            label: 'Owner name',
            hint: 'Enter your full name',
          ),
          const SizedBox(height: 12),
          _buildInputField(
            controller: _phoneController,
            label: 'Phone number',
            hint: 'Enter contact phone number',
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 16),
          _buildSaveButton(),
        ],
      ),
    );
  }

  Widget _buildEditableStationForm() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return PortalCard(
      lift: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: _isUploadingStationPhoto ? null : _pickAndUploadStationPhoto,
            child: Container(
              height: 120,
              width: double.infinity,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant),
                image: _stationPhotoUrl != null
                    ? DecorationImage(image: NetworkImage(_stationPhotoUrl!), fit: BoxFit.cover)
                    : null,
              ),
              child: _isUploadingStationPhoto
                  ? const Center(child: CircularProgressIndicator())
                  : (_stationPhotoUrl == null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_a_photo_outlined, color: scheme.onSurfaceVariant),
                              const SizedBox(height: 4),
                              Text(
                                'Add station photo',
                                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        )
                      : Align(
                          alignment: Alignment.bottomRight,
                          child: Container(
                            margin: const EdgeInsets.all(8),
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                            child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                          ),
                        )),
            ),
          ),
          const SizedBox(height: 16),
          _buildInputField(
            controller: _stationNameController,
            label: 'Station name',
            hint: 'Your station name',
          ),
          const SizedBox(height: 12),
          _buildInputField(
            controller: _stationAddressController,
            label: 'Station address',
            hint: 'Full address for customers',
            maxLines: 3,
          ),
          const SizedBox(height: 12),
          _buildInputField(
            controller: _emailController,
            label: 'Email',
            hint: 'Your contact email',
            readOnly: true,
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _isAcceptingOrders,
            onChanged: (v) => setState(() => _isAcceptingOrders = v),
            title: Text('Accepting orders', style: theme.textTheme.titleSmall),
            subtitle: Text(
              'Turn off when closed -- customers will see this station as closed and can\'t order.',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          const Divider(),
          // Water types and containers used to be chips here, with no price
          // anywhere. They now come from the station's products, where each
          // one carries its own price.
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.sell_outlined),
            title: Text('Products & prices', style: theme.textTheme.titleSmall),
            subtitle: Text(
              'Water types, containers, prices and delivery fee',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, appRoute(const ProductsScreen())),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _offersJugExchange,
            onChanged: (v) => setState(() => _offersJugExchange = v),
            title: Text('Accepts jug exchange', style: theme.textTheme.titleSmall),
            subtitle: Text(
              'Customers can bring an empty jug of any brand and swap it for a full one.',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          const Divider(),
          const SizedBox(height: 4),
          Text('Operating hours', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Leave every day checked with no times set to stay always open.',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final entry in const {1: 'Mon', 2: 'Tue', 3: 'Wed', 4: 'Thu', 5: 'Fri', 6: 'Sat', 7: 'Sun'}.entries)
                FilterChip(
                  label: Text(entry.value),
                  selected: _operatingDays.contains(entry.key),
                  onSelected: (v) => setState(() => v ? _operatingDays.add(entry.key) : _operatingDays.remove(entry.key)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Two buttons in Expandeds is the pattern that overflowed a 360px
          // phone at large text on Orders, so the hours go through the same
          // action row that stacks them when they don't fit.
          PortalActionRow(
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showTimePicker(context: context, initialTime: _opensAt ?? const TimeOfDay(hour: 7, minute: 0));
                  if (picked != null) setState(() => _opensAt = picked);
                },
                icon: const Icon(Icons.schedule, size: 18),
                label: Text(_opensAt == null ? 'Opens...' : 'Opens ${_opensAt!.format(context)}'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showTimePicker(context: context, initialTime: _closesAt ?? const TimeOfDay(hour: 19, minute: 0));
                  if (picked != null) setState(() => _closesAt = picked);
                },
                icon: const Icon(Icons.schedule, size: 18),
                label: Text(_closesAt == null ? 'Closes...' : 'Closes ${_closesAt!.format(context)}'),
              ),
            ],
          ),
          if (_opensAt != null || _closesAt != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Clear hours'),
                onPressed: () => setState(() {
                  _opensAt = null;
                  _closesAt = null;
                }),
              ),
            ),
          const SizedBox(height: 16),
          _buildSaveButton(),
        ],
      ),
    );
  }

  Widget _buildLocationForm() {
    return PortalCard(
      lift: false,
      child: Column(
        children: [
          StatusCallout(
            accent: Theme.of(context).colorScheme.primary,
            icon: Icons.map_outlined,
            title: 'Add your station location so customers can find you on the map.',
          ),
          const SizedBox(height: 16),
          _buildInputField(
            controller: _latitudeController,
            label: 'Latitude',
            hint: 'e.g., 14.3868',
          ),
          const SizedBox(height: 12),
          _buildInputField(
            controller: _longitudeController,
            label: 'Longitude',
            hint: 'e.g., 120.8817',
          ),
          const SizedBox(height: 16),
          PortalActionRow(
            children: [
              OutlinedButton.icon(
                onPressed: _openLocationPicker,
                icon: const Icon(Icons.location_on),
                label: const Text('Pick from map'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildSaveButton(label: 'Save location'),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
    bool readOnly = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return TextField(
      controller: controller,
      maxLines: maxLines,
      readOnly: readOnly,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        // A read-only field is filled so it reads as "shown, not editable" --
        // it used to be a fixed grey.shade100, which was all but invisible in
        // dark mode.
        filled: readOnly,
        fillColor: readOnly ? scheme.surfaceContainerHighest : Colors.transparent,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
    );
  }
}
