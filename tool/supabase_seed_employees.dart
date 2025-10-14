import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:supabase/supabase.dart';

import 'package:oldies_workers_app/config/app_config.dart';

final _seedEmployees = [
  (
    id: 'EMP001',
    name: 'مريم حسن',
    email: 'maryam.hassan@example.com',
    pin: '1234',
    role: 'admin',
    permissions: [
      'manageEmployees',
      'monitorAccess',
      'viewPayroll',
    ],
    branch: 'الفرع الرئيسي - الزمالك',
    salary: 18500.0,
  ),
  (
    id: 'EMP002',
    name: 'عمر سعيد',
    email: 'omar.saeed@example.com',
    pin: '5678',
    role: 'hr',
    permissions: [
      'viewPayroll',
      'manageScheduling',
    ],
    branch: 'فرع المعادي',
    salary: 13250.0,
  ),
  (
    id: 'EMP003',
    name: 'نورة عادل',
    email: 'noura.adel@example.com',
    pin: '2468',
    role: 'monitor',
    permissions: [
      'monitorAccess',
    ],
    branch: 'فرع مدينة نصر',
    salary: 9800.0,
  ),
];

String _hashPin(String pin) => sha256.convert(utf8.encode(pin)).toString();

Future<void> main(List<String> arguments) async {
  final client = SupabaseClient(
    AppConfig.supabaseUrl,
    AppConfig.supabaseAnonKey,
  );

  print('➡️  Seeding ${_seedEmployees.length} employees into Supabase...');

  for (final employee in _seedEmployees) {
    final payload = {
      'id': employee.id,
      'full_name': employee.name,
  'work_email': employee.email,
      'pin_hash': _hashPin(employee.pin),
      'role': employee.role,
      'permissions': employee.permissions,
      'branch': employee.branch,
      'monthly_salary': employee.salary,
      'active': true,
    };

    try {
      await client.from('employees').upsert(payload);
    } on PostgrestException catch (error) {
      throw StateError('Failed to upsert employee ${employee.id}: ${error.message}');
    }

    print('✔️  Upserted employee ${employee.id}');
  }

  print('✅ Supabase employee seeding completed.');
}
