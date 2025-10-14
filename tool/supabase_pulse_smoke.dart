import 'dart:math';

import 'package:supabase/supabase.dart';

import 'package:oldies_workers_app/config/app_config.dart';

Future<void> main(List<String> args) async {
  final client = SupabaseClient(
    AppConfig.supabaseUrl,
    AppConfig.supabaseAnonKey,
  );

  final now = DateTime.now().toUtc();
  final random = Random();
  final employeeId = args.isNotEmpty ? args.first : 'EMP001';
  final pulsePayload = {
    'employee_id': employeeId,
    'latitude': 30.0 + random.nextDouble() * 0.01,
    'longitude': 31.0 + random.nextDouble() * 0.01,
    'timestamp': now.toIso8601String(),
    'is_fake': false,
    'sent_from_device': true,
    'sent_via_supabase': true,
  };

  final insertResponse = await client
  .from(AppConfig.supabasePulseTable)
  .insert(pulsePayload)
  .select();

  if (insertResponse.isEmpty) {
    throw StateError('Insert did not return created row. Response: $insertResponse');
  }

  print('✔ Pulse inserted into Supabase for employee $employeeId');

  final verifyResponse = await client
      .from(AppConfig.supabasePulseTable)
      .select()
      .eq('employee_id', employeeId)
      .eq('timestamp', pulsePayload['timestamp'] as String)
      .limit(1);

  if (verifyResponse.isEmpty) {
    throw StateError('Inserted pulse not found during verification.');
  }

  print('✔ Pulse verified in Supabase with row: ${verifyResponse.first}');

  try {
    await client
    .from(AppConfig.supabasePulseTable)
    .delete()
    .eq('employee_id', employeeId)
    .eq('timestamp', pulsePayload['timestamp'] as String);
    print('✔ Cleaned up smoke-test row.');
  } catch (error) {
    print('⚠️ Failed to clean up smoke-test row: $error');
  }

  print('Supabase pulse smoke test completed successfully.');
}
