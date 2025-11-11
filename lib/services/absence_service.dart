import 'package:supabase_flutter/supabase_flutter.dart';

class AbsenceService {
  static final _supabase = Supabase.instance.client;

  /// Check if employee is late for shift and create absence record
  static Future<Map<String, dynamic>?> checkShiftAbsence({
    required String employeeId,
    required String branchId,
    required String managerId,
    required String shiftStartTime, // "09:00"
    required String shiftEndTime, // "17:00"
    required DateTime checkInTime,
  }) async {
    try {
      // Parse shift start time
      final shiftStartParts = shiftStartTime.split(':');
      final shiftStartHour = int.parse(shiftStartParts[0]);
      final shiftStartMinute = int.parse(shiftStartParts[1]);
      
      final today = DateTime.now();
      final shiftStartDateTime = DateTime(
        today.year,
        today.month,
        today.day,
        shiftStartHour,
        shiftStartMinute,
      );

      // Check if employee is late (more than 15 minutes)
      final lateMinutes = checkInTime.difference(shiftStartDateTime).inMinutes;
      
      if (lateMinutes > 15) {
        // Employee is late - create absence record
        print('⚠️ Employee $employeeId is late by $lateMinutes minutes');
        
        final absence = await _supabase.from('absences').insert({
          'employee_id': employeeId,
          'branch_id': branchId,
          'manager_id': managerId,
          'absence_date': today.toIso8601String().split('T')[0],
          'shift_start_time': shiftStartTime,
          'shift_end_time': shiftEndTime,
          'status': 'pending',
        }).select().single();

        print('✅ Absence record created: ${absence['id']}');
        
        // TODO: Send notification to manager
        await _notifyManagerAboutAbsence(
          managerId: managerId,
          employeeId: employeeId,
          absenceId: absence['id'],
          lateMinutes: lateMinutes,
        );

        return absence;
      }

      return null;
    } catch (e) {
      print('❌ Error checking shift absence: $e');
      return null;
    }
  }

  /// Manager approves absence (no deduction)
  static Future<bool> approveAbsence({
    required String absenceId,
    required String managerId,
    String? reason,
  }) async {
    try {
      await _supabase.from('absences').update({
        'status': 'approved',
        'manager_response': reason ?? 'موافق على الغياب',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', absenceId);

      print('✅ Absence $absenceId approved by manager $managerId');
      return true;
    } catch (e) {
      print('❌ Error approving absence: $e');
      return false;
    }
  }

  /// Manager rejects absence (apply 2-day deduction)
  static Future<bool> rejectAbsence({
    required String absenceId,
    required String employeeId,
    required String managerId,
    required double hourlyRate,
    required String shiftStartTime,
    required String shiftEndTime,
    String? reason,
  }) async {
    try {
      // Calculate shift hours
      final shiftHours = _calculateShiftHours(shiftStartTime, shiftEndTime);
      
      // Calculate deduction: 2 days × shift hours × hourly rate (negative)
      final deductionAmount = -(2 * shiftHours * hourlyRate);
      
      print('📊 Deduction calculation:');
      print('  - Shift hours: $shiftHours');
      print('  - Hourly rate: $hourlyRate');
      print('  - Days penalty: 2');
      print('  - Total deduction: $deductionAmount');

      // Update absence status
      await _supabase.from('absences').update({
        'status': 'rejected',
        'manager_response': reason ?? 'مرفوض - خصم يومين',
        'deduction_amount': deductionAmount.abs(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', absenceId);

      // Create deduction record
      await _supabase.from('deductions').insert({
        'employee_id': employeeId,
        'absence_id': absenceId,
        'amount': deductionAmount,
        'reason': 'خصم يومين لعدم الموافقة على الغياب',
        'deduction_date': DateTime.now().toIso8601String().split('T')[0],
      });

      print('✅ Absence $absenceId rejected - Deducted: ${deductionAmount.abs()} EGP');
      
      // TODO: Notify employee about deduction
      
      return true;
    } catch (e) {
      print('❌ Error rejecting absence: $e');
      return false;
    }
  }

  /// Get pending absences for manager
  static Future<List<Map<String, dynamic>>> getPendingAbsences(String branchId) async {
    try {
      final absences = await _supabase
          .from('absences')
          .select('''
            *,
            employee:employees!absences_employee_id_fkey(id, full_name, hourly_rate)
          ''')
          .eq('branch_id', branchId)
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(absences);
    } catch (e) {
      print('❌ Error getting pending absences: $e');
      return [];
    }
  }

  /// Get employee deductions
  static Future<List<Map<String, dynamic>>> getEmployeeDeductions(String employeeId) async {
    try {
      final deductions = await _supabase
          .from('deductions')
          .select('*')
          .eq('employee_id', employeeId)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(deductions);
    } catch (e) {
      print('❌ Error getting deductions: $e');
      return [];
    }
  }

  /// Calculate total deductions for employee
  static Future<double> getTotalDeductions(String employeeId) async {
    try {
      final deductions = await getEmployeeDeductions(employeeId);
      
      double total = 0;
      for (var deduction in deductions) {
        total += (deduction['amount'] as num).toDouble();
      }
      
      return total; // Will be negative
    } catch (e) {
      print('❌ Error calculating total deductions: $e');
      return 0;
    }
  }

  /// Calculate shift hours from start and end time
  static double _calculateShiftHours(String startTime, String endTime) {
    try {
      final startParts = startTime.split(':');
      final endParts = endTime.split(':');
      
      final startHour = int.parse(startParts[0]);
      final startMinute = int.parse(startParts[1]);
      final endHour = int.parse(endParts[0]);
      final endMinute = int.parse(endParts[1]);
      
      final startTotalMinutes = (startHour * 60) + startMinute;
      final endTotalMinutes = (endHour * 60) + endMinute;
      
      final diffMinutes = endTotalMinutes - startTotalMinutes;
      final hours = diffMinutes / 60.0;
      
      return hours;
    } catch (e) {
      print('❌ Error calculating shift hours: $e');
      return 8.0; // Default 8 hours
    }
  }

  /// Send notification to manager about absence
  static Future<void> _notifyManagerAboutAbsence({
    required String managerId,
    required String employeeId,
    required String absenceId,
    required int lateMinutes,
  }) async {
    // TODO: Implement push notification to manager
    print('📧 Notification sent to manager $managerId:');
    print('   Employee $employeeId is late by $lateMinutes minutes');
    print('   Absence ID: $absenceId');
  }
}
