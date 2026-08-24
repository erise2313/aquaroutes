import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin singleton wrapper around the Supabase client. Every domain service
/// (AuthService, StationService, OrderService, etc.) depends on this instead
/// of calling `Supabase.instance.client` directly, so there is a single
/// choke point for client access.
class SupabaseService {
  SupabaseService._();

  static final SupabaseService instance = SupabaseService._();

  SupabaseClient get client => Supabase.instance.client;
}
