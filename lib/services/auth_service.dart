import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient supabase = Supabase.instance.client;


  // --- ADD THIS METHOD HERE ---
  Future<String?> sendPasswordResetEmail(String email) async {
    try {
      await supabase.auth.resetPasswordForEmail(
        email.trim(),
        // Point this to your Next.js web application reset page
        redirectTo: 'http://localhost:3000/reset-password', 
      );
      return null; // Success (no error message)
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return 'Unexpected error: $e';
    }
  }

  Future<String?> signInFarmer({
    required String email,
    required String password,
  }) async {
    try {
      // 1. Authenticate with Supabase
      final response = await supabase.auth.signInWithPassword(
        email: email.trim(),
        password: password.trim(),
      );

      final user = response.user;
      if (user == null) {
        return 'Login failed. Please check your credentials.';
      }

      // 2. Security Check: Are they actually a farmer?
      final profile = await supabase
          .from('users')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      if (profile == null) {
        await supabase.auth.signOut();
        return 'Error: Account profile not found in database.';
      }

      final role = profile['role']?.toString();
      if (role != 'farmer') {
        await supabase.auth.signOut();
        return 'Access Denied: This app is for Farmers only.';
      }

      // Success!
      return null;
    } on AuthException catch (e) {
      return e.message; // Returns Supabase errors like "Invalid login credentials"
    } catch (e) {
      return 'Unexpected error: $e';
    }
  }

  Future<void> signOut() async {
    await supabase.auth.signOut();
  }
}