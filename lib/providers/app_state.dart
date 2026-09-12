import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_notification.dart';
import '../models/membership.dart';
import '../models/station.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
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

/// Whether anyone is signed in at all.
///
/// Deliberately keyed on the session rather than the membership: the nav bar
/// uses this to decide whether to show Login/Register or the account menu, and
/// waiting for currentMembershipProvider would flash the signed-out actions on
/// every page load while that query is still in flight.
final isSignedInProvider = Provider<bool>((ref) {
  return ref.watch(authStateProvider).value?.session != null;
});

/// The signed-in user's role once it resolves, or null while it is still
/// loading or nobody is signed in. One source of truth for "what are they",
/// so the shell doesn't re-derive it from two async providers at each use.
final signedInRoleProvider = Provider<AppRole?>((ref) {
  if (!ref.watch(isSignedInProvider)) return null;
  return ref.watch(currentMembershipProvider).value?.role;
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

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService(ref.watch(supabaseServiceProvider));
});

/// The signed-in user's in-app notifications, newest first, kept live by
/// Realtime. Re-subscribes on sign-in/out; empty for a signed-out visitor.
final notificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.when(
    data: (_) => ref.watch(notificationServiceProvider).watch(),
    loading: () => Stream.value(const <AppNotification>[]),
    error: (_, _) => Stream.value(const <AppNotification>[]),
  );
});

final unreadNotificationCountProvider = Provider<int>((ref) {
  return ref.watch(notificationsProvider).value?.where((n) => !n.isRead).length ?? 0;
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
