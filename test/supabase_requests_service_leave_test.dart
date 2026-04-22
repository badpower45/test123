import 'package:flutter_test/flutter_test.dart';

import 'package:at_app/services/supabase_requests_service.dart';

void main() {
  tearDown(() {
    SupabaseRequestsService.setLeaveRequestInsertHandlerForTesting(null);
  });

  test('createLeaveRequest builds expected payload and returns inserted row', () async {
    Map<String, dynamic>? capturedPayload;

    SupabaseRequestsService.setLeaveRequestInsertHandlerForTesting((payload) async {
      capturedPayload = payload;
      return {
        'id': 'leave_123',
        ...payload,
      };
    });

    final result = await SupabaseRequestsService.createLeaveRequest(
      employeeId: 'EMP001',
      leaveType: 'emergency',
      startDate: DateTime(2026, 4, 1, 8, 30),
      endDate: DateTime(2026, 4, 3, 17, 45),
      reason: 'ظرف طارئ',
    );

    expect(result, isNotNull);
    expect(result!['id'], 'leave_123');

    expect(capturedPayload, isNotNull);
    expect(capturedPayload!['employee_id'], 'EMP001');
    expect(capturedPayload!['leave_type'], 'emergency');
    expect(capturedPayload!['start_date'], '2026-04-01');
    expect(capturedPayload!['end_date'], '2026-04-03');
    expect(capturedPayload!['reason'], 'ظرف طارئ');
    expect(capturedPayload!['status'], 'pending');
  });

  test('createLeaveRequest returns null when insert handler throws', () async {
    SupabaseRequestsService.setLeaveRequestInsertHandlerForTesting((_) async {
      throw Exception('network down');
    });

    final result = await SupabaseRequestsService.createLeaveRequest(
      employeeId: 'EMP001',
      leaveType: 'normal',
      startDate: DateTime(2026, 4, 5),
      endDate: DateTime(2026, 4, 5),
      reason: 'طلب إجازة',
    );

    expect(result, isNull);
  });
}
