import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:supabase/supabase.dart';

import 'package:oldies_workers_app/config/app_config.dart';

class _AccountSeed {
  const _AccountSeed({
    required this.employeeId,
    required this.fullName,
    required this.email,
    required this.password,
    required this.pin,
    required this.role,
    required this.permissions,
    required this.branch,
    required this.salary,
  });

  final String employeeId;
  final String fullName;
  final String email;
  final String password;
  final String pin;
  final String role;
  final List<String> permissions;
  final String branch;
  final double salary;
}

final _seedAccounts = <_AccountSeed>[
  const _AccountSeed(
    employeeId: 'OWNER001',
    fullName: 'محمد أحمد - المالك',
    email: 'owner@oldies.com',
    password: 'Oldies#Owner1',
    pin: '0000',
    role: 'owner',
    permissions: ['manageEmployees', 'monitorAccess', 'viewPayroll', 'manageBranches'],
    branch: 'جميع الفروع',
    salary: 50000,
  ),
  const _AccountSeed(
    employeeId: 'EMP001',
    fullName: 'مريم حسن',
    email: 'maryam.hassan@example.com',
    password: 'Oldies#Maryam1',
    pin: '1234',
    role: 'admin',
    permissions: ['manageEmployees', 'monitorAccess', 'viewPayroll'],
    branch: 'الفرع الرئيسي - الزمالك',
    salary: 18500,
  ),
  const _AccountSeed(
    employeeId: 'EMP002',
    fullName: 'عمر سعيد',
    email: 'omar.saeed@example.com',
    password: 'Oldies#Omar2',
    pin: '5678',
    role: 'hr',
    permissions: ['viewPayroll', 'manageScheduling'],
    branch: 'فرع المعادي',
    salary: 13250,
  ),
  const _AccountSeed(
    employeeId: 'EMP003',
    fullName: 'نورة عادل',
    email: 'noura.adel@example.com',
    password: 'Oldies#Noura3',
    pin: '2468',
    role: 'monitor',
    permissions: ['monitorAccess'],
    branch: 'فرع مدينة نصر',
    salary: 9800,
  ),
];

String _hashPin(String pin) => sha256.convert(pin.codeUnits).toString();

Future<void> main(List<String> args) async {
  final serviceRoleKey = Platform.environment['SUPABASE_SERVICE_ROLE_KEY'];
  if (serviceRoleKey == null || serviceRoleKey.isEmpty) {
    stderr
      ..writeln('❌ Missing SUPABASE_SERVICE_ROLE_KEY environment variable.')
      ..writeln(
        'Set your Supabase service role key before running this script. Example:',
      )
      ..writeln('  setx SUPABASE_SERVICE_ROLE_KEY "your-service-role-key"');
    exitCode = 64;
    return;
  }

  final adminClient = SupabaseClient(
    AppConfig.supabaseUrl,
    serviceRoleKey,
  );

  for (final account in _seedAccounts) {
    final userId = await _ensureAuthUser(adminClient, account);
    await _upsertProfile(adminClient, userId, account);
    await _upsertEmployee(adminClient, account);
    stdout.writeln('✔ Created/updated account for ${account.employeeId} (${account.email})');
  }

  stdout.writeln('✅ Supabase accounts seeded successfully.');
}

Future<String> _ensureAuthUser(
  SupabaseClient client,
  _AccountSeed account,
) async {
  try {
    final response = await client.auth.admin.createUser(
      AdminUserAttributes(
        email: account.email,
        password: account.password,
        emailConfirm: true,
        userMetadata: {
          'employee_id': account.employeeId,
          'role': account.role,
        },
      ),
    );
    final user = response.user;
    if (user == null) {
      throw Exception('User creation response missing user object.');
    }
    return user.id;
  } on AuthException catch (error) {
    if (!error.message.toLowerCase().contains('already registered')) {
      rethrow;
    }
    final existing = await _findUserByEmail(client, account.email);
    if (existing == null) {
      throw Exception('User ${account.email} exists but could not be fetched.');
    }
    return existing.id;
  }
}

Future<User?> _findUserByEmail(SupabaseClient client, String email) async {
  final users = await client.auth.admin.listUsers(perPage: 200, page: 1);
  for (final user in users) {
    if (user.email?.toLowerCase() == email.toLowerCase()) {
      return user;
    }
  }
  return null;
}

Future<void> _upsertProfile(
  SupabaseClient client,
  String userId,
  _AccountSeed account,
) async {
  await client.from('profiles').upsert({
    'id': userId,
    'full_name': account.fullName,
    'employee_id': account.employeeId,
    'role': account.role,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  });
}

Future<void> _upsertEmployee(
  SupabaseClient client,
  _AccountSeed account,
) async {
  await client.from('employees').upsert({
    'id': account.employeeId,
    'full_name': account.fullName,
    'work_email': account.email,
    'pin_hash': _hashPin(account.pin),
    'role': account.role,
    'permissions': account.permissions,
    'branch': account.branch,
    'monthly_salary': account.salary,
    'active': true,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  });
}
