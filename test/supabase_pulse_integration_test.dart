@Tags(['supabase'])
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:oldies_workers_app/config/app_config.dart';
import 'package:oldies_workers_app/models/pulse.dart';
import 'package:oldies_workers_app/services/pulse_backend_client.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets(
    'PulseBackendClient sends and persists to Supabase',
    (tester) async {
      await HttpOverrides.runWithHttpOverrides(() async {
        // Removed: PulseBackendClient.resetTestingOverrides (method does not exist)
        await PulseBackendClient.initialize();

        final now = DateTime.now().toUtc();
        final random = Random();
        final pulse = Pulse(
          employeeId: 'INT_${now.microsecondsSinceEpoch}',
          latitude: 30.0 + random.nextDouble() * 0.01,
          longitude: 31.0 + random.nextDouble() * 0.01,
          timestamp: now,
          isFake: false,
        );

        final sent = await PulseBackendClient.sendPulse(pulse);
        expect(sent, isTrue, reason: 'Supabase insert should succeed');

        final client = Supabase.instance.client;
        final rows = await client
            .from(AppConfig.supabasePulseTable)
            .select()
            .eq('employeeId', pulse.employeeId)
            .eq('timestamp', pulse.timestamp.toIso8601String())
            .limit(1);

        expect(rows, isNotEmpty, reason: 'Inserted pulse must exist in Supabase');

        await client
            .from(AppConfig.supabasePulseTable)
            .delete()
            .eq('employeeId', pulse.employeeId);
      }, _AllowRealHttpOverrides());
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

class _AllowRealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback = (_, __, ___) => true;
    return client;
  }
}
