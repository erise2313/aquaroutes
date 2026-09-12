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
import '../../widgets/account_settings_section.dart';
import '../../widgets/app_theme_toggle.dart';
import '../../widgets/status_callout.dart';
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
      appBar: AppBar(
        title: Text(
          "Station Profile",
          style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
        ),
        elevation: 0,
        actions: const [AppThemeToggle()],
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : _buildProfileContent(),
    );
  }

  Widget _buildProfileContent() {
    final String ownerName = _profileData?['full_name'] ?? "Unknown Owner";
    final String stationName = _stationData?['station_name'] ?? "Unnamed Station";
    final String email = supabase.auth.currentUser?.email ?? "";
    final bool isAccredited = _stationData?['is_accredited'] as bool? ?? false;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade600,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue.withValues(alpha: 0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
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
                                      : (_avatarUrl == null ? const Icon(Icons.storefront, size: 35, color: Colors.blue) : null),
                                ),
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
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
                                Text(
                                  ownerName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "$stationName\n$email",
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 24),
                    _buildAccreditationBanner(isAccredited),
                    const SizedBox(height: 24),
                    DefaultTabController(
                      length: 3,
                      initialIndex: _selectedTabIndex,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TabBar(
                            onTap: (index) => setState(() => _selectedTabIndex = index),
                            labelColor: Colors.blue.shade700,
                            unselectedLabelColor: Colors.grey,
                            indicatorColor: Colors.blue.shade700,
                            tabs: const [
                              Tab(text: 'Profile'),
                              Tab(text: 'Station Info'),
                              Tab(text: 'Location'),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            // TabBarView needs a bounded height, but a fixed
                            // one clipped the forms once the system font size
                            // was turned up, so it grows with it.
                            height: 380 * MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 2.0).toDouble(),
                            child: TabBarView(
                              children: [
                                _buildEditableProfileForm(),
                                _buildEditableStationForm(),
                                _buildLocationForm(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(context, appRoute(const AboutWasaHubScreen())),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.info_outline),
              label: const Text('WASA Resources'),
            ),
            const SizedBox(height: 16),
            const Card(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: AccountSettingsSection(),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _isLoggingOut ? null : _logout,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent, width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: _isLoggingOut
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.redAccent,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.logout),
              label: const Text(
                "SECURE LOGOUT",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccreditationBanner(bool isAccredited) {
    if (isAccredited) {
      return const StatusCallout(
        accent: Colors.green,
        icon: Icons.verified,
        title: 'WASA Accredited. Your station is visible to the public.',
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: StatusTint.surface(context, Colors.amber),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: StatusTint.border(context, Colors.amber)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Colors.amber.shade700,
                size: 28,
              ),
              const SizedBox(width: 12),
              const Text(
                "Action Required",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "Your station isn't accredited yet. Upload your permits so WASA can review them.",
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => Navigator.push(context, appRoute(const PermitVaultScreen())),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade600,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.upload_file),
            label: const Text(
              "OPEN PERMIT VAULT",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableProfileForm() {
    return SingleChildScrollView(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Column(
          children: [
            _buildInputField(
              controller: _fullNameController,
              label: 'Owner Name',
              hint: 'Enter your full name',
            ),
            const SizedBox(height: 12),
            _buildInputField(
              controller: _phoneController,
              label: 'Phone Number',
              hint: 'Enter contact phone number',
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveProfile,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: Text(_isSaving ? 'Saving...' : 'Save Changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditableStationForm() {
    return SingleChildScrollView(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Column(
          children: [
            GestureDetector(
              onTap: _isUploadingStationPhoto ? null : _pickAndUploadStationPhoto,
              child: Container(
                height: 120,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
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
                                Icon(Icons.add_a_photo_outlined, color: Colors.grey.shade700),
                                const SizedBox(height: 4),
                                Text('Add Station Photo', style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
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
              label: 'Station Name',
              hint: 'Your station name',
            ),
            const SizedBox(height: 12),
            _buildInputField(
              controller: _stationAddressController,
              label: 'Station Address',
              hint: 'Full address for customers',
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            _buildInputField(
              controller: _emailController,
              label: 'Email',
              hint: 'Your contact email',
              readOnly: true,
              backgroundColor: Colors.grey.shade100,
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isAcceptingOrders,
              onChanged: (v) => setState(() => _isAcceptingOrders = v),
              title: const Text('Accepting Orders', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Turn off when closed -- customers will see this station as closed and can\'t order.', style: TextStyle(fontSize: 12)),
            ),
            const Divider(),
            // Water types and containers used to be chips here, with no price
            // anywhere. They now come from the station's products, where each
            // one carries its own price.
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.sell_outlined),
              title: const Text('Products & prices', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Water types, containers, prices and delivery fee', style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, appRoute(const ProductsScreen())),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _offersJugExchange,
              onChanged: (v) => setState(() => _offersJugExchange = v),
              title: const Text('Accepts Jug Exchange', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Customers can bring an empty jug of any brand and swap it for a full one.', style: TextStyle(fontSize: 12)),
            ),
            const Divider(),
            const Align(alignment: Alignment.centerLeft, child: Text('Operating Hours', style: TextStyle(fontWeight: FontWeight.w600))),
            const SizedBox(height: 4),
            const Text(
              'Leave every day checked with no times set to stay always-open (today\'s default behavior).',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
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
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showTimePicker(context: context, initialTime: _opensAt ?? const TimeOfDay(hour: 7, minute: 0));
                      if (picked != null) setState(() => _opensAt = picked);
                    },
                    icon: const Icon(Icons.schedule, size: 18),
                    label: Text(_opensAt == null ? 'Opens...' : 'Opens ${_opensAt!.format(context)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showTimePicker(context: context, initialTime: _closesAt ?? const TimeOfDay(hour: 19, minute: 0));
                      if (picked != null) setState(() => _closesAt = picked);
                    },
                    icon: const Icon(Icons.schedule, size: 18),
                    label: Text(_closesAt == null ? 'Closes...' : 'Closes ${_closesAt!.format(context)}'),
                  ),
                ),
                if (_opensAt != null || _closesAt != null)
                  IconButton(
                    tooltip: 'Clear hours',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      _opensAt = null;
                      _closesAt = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveProfile,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: Text(_isSaving ? 'Saving...' : 'Save Changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationForm() {
    return SingleChildScrollView(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: const Text(
                'Add your station location so customers can find you on the map.',
                style: TextStyle(fontSize: 12, color: Colors.blue),
              ),
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
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _openLocationPicker,
                icon: const Icon(Icons.location_on),
                label: const Text('Pick from Map'),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveProfile,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: Text(_isSaving ? 'Saving...' : 'Save Location'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
    bool readOnly = false,
    Color? backgroundColor,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      readOnly: readOnly,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: readOnly || backgroundColor != null,
        fillColor: backgroundColor ?? Colors.transparent,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.blue.shade500, width: 2),
        ),
      ),
    );
  }
}
