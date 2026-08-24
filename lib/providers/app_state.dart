import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/membership.dart';
import '../models/station.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';

final supabaseServiceProvider = Provider<SupabaseService>((ref) => SupabaseService.instance);

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(supabaseServiceProvider));
});

/// Emits whenever the user signs in/out/session refreshes.
final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

/// The signed-in user's membership (role + station scope), re-fetched every
/// time the auth state changes. Null means "no membership" -- a legacy or
/// unassigned account, since public consumers never sign in at all.
final currentMembershipProvider = FutureProvider<Membership?>((ref) async {
  final authState = ref.watch(authStateProvider);
  return authState.when(
    data: (_) => ref.watch(authServiceProvider).fetchCurrentMembership(),
    loading: () => null,
    error: (_, _) => null,
  );
});

/// Only evaluated by AuthGate when currentMembershipProvider resolves to
/// null, to distinguish "no membership row at all" (null here too) from
/// "a membership row exists but isn't active" (the raw status string) --
/// fetchCurrentMembership can't tell those apart since it filters
/// status = 'active'.
final rawMembershipStatusProvider = FutureProvider<String?>((ref) async {
  final authState = ref.watch(authStateProvider);
  return authState.when(
    data: (_) => ref.watch(authServiceProvider).fetchRawMembershipStatus(),
    loading: () => null,
    error: (_, _) => null,
  );
});

/// The station the signed-in user (station_owner or driver) is scoped to,
/// resolved via their membership's station_id.
final currentStationProvider = FutureProvider<Station?>((ref) async {
  final membership = await ref.watch(currentMembershipProvider.future);
  final stationId = membership?.stationId;
  if (stationId == null) return null;

  final row = await ref
      .watch(supabaseServiceProvider)
      .client
      .from('water_stations')
      .select()
      .eq('id', stationId)
      .maybeSingle();

  if (row == null) return null;
  return Station.fromMap(row);
});
