import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  static const String supabaseUrl = 'https://bbxuyuaemigrqsvsnxkj.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJieHV5dWFlbWlncnFzdnNueGtqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjI2MDkyNDAsImV4cCI6MjA3ODE4NTI0MH0.ZZF3qo7FAM4QpRkcqYb0N4bqw-mFGeRI90kYDDUnE4c';

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      realtimeClientOptions: const RealtimeClientOptions(
        timeout: Duration(seconds: 30),
      ),
    );
    
    print('✅ Supabase initialized successfully');
  }

  static SupabaseClient get client => Supabase.instance.client;
}
