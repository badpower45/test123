import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_colors.dart';
import '../../services/supabase_function_client.dart';
import '../employee/employee_payroll_report_page.dart';

class OwnerSalariesScreen extends StatefulWidget {
  const OwnerSalariesScreen({super.key});
  @override
  State<OwnerSalariesScreen> createState() => _OwnerSalariesScreenState();
}

class _OwnerSalariesScreenState extends State<OwnerSalariesScreen> {
  bool _loading = true; String? _error; List<Map<String,dynamic>> _rows = []; 
  @override
  void initState(){ super.initState(); _load(); }

  Future<void> _load() async {
    setState(()=>_loading=true); 
    final client = Supabase.instance.client; 
    try {
      print('🔍 [Salaries] Starting to load salary data...');
      
      // محاولة جلب البيانات من الـ table/view
      List<dynamic> salariesResp = [];
      try {
        salariesResp = await client
            .from('up_to_date_salary_with_advances')
            .select('*')
            .order('employee_id');
        print('📊 [Salaries] Query successful, found ${salariesResp.length} records');
      } catch (queryError) {
        print('❌ [Salaries] Query error: $queryError');
        // محاولة بديلة: جلب من employees مع join
        print('🔄 [Salaries] Trying alternative approach...');
        salariesResp = [];
      }
      
      // إذا مفيش بيانات في الـ view، نجرب نعمل join مع employees
      if (salariesResp.isEmpty) {
        print('⚠️ [Salaries] No data in view, trying to get from employees...');
        
        // جلب جميع الموظفين النشطين
        final employeesResp = await client
            .from('employees')
            .select('id, full_name, role, branch')
            .eq('is_active', true);
        
        print('👥 [Salaries] Found ${(employeesResp as List).length} active employees');
        
        // محاولة جلب بيانات الرواتب لكل موظف
        final List<Map<String,dynamic>> list = [];
        for (final emp in (employeesResp as List)) {
          final empId = emp['id'] as String;
          
          // جلب period earnings من الـ function (نفس المربع الأزرق)
          double periodEarnings = 0.0;
          try {
            final periodResult = await SupabaseFunctionClient.post('employee-period-earnings', {
              'employee_id': empId,
            });
            
            if ((periodResult ?? {})['success'] == true) {
              final totals = (periodResult ?? {})['totals'] as Map<String, dynamic>?;
              periodEarnings = (totals?['net'] as num?)?.toDouble() ?? 0.0;
            }
          } catch (e) {
            print('⚠️ [Salaries] Failed to load period earnings for $empId: $e');
          }
          
          // محاولة جلب بيانات الراتب الإضافية من الـ view
          try {
            final salaryData = await client
                .from('up_to_date_salary_with_advances')
                .select('*')
                .eq('employee_id', empId)
                .maybeSingle();
            
            list.add({
              'id': empId,
              'full_name': emp['full_name'] ?? 'غير معروف',
              'role': emp['role'] ?? '—',
              'branch': emp['branch'] ?? '—',
              'current_salary': periodEarnings, // استخدام period earnings
              'total_net_salary': (salaryData?['total_net_salary'] as num?)?.toDouble() ?? 0.0,
              'total_approved_advances': (salaryData?['total_approved_advances'] as num?)?.toDouble() ?? 0.0,
              'available_advance': (salaryData?['available_advance_30_percent'] as num?)?.toDouble() ?? 0.0,
            });
          } catch (e) {
            // إذا مفيش بيانات، نضيف الموظف بـ period earnings فقط
            list.add({
              'id': empId,
              'full_name': emp['full_name'] ?? 'غير معروف',
              'role': emp['role'] ?? '—',
              'branch': emp['branch'] ?? '—',
              'current_salary': periodEarnings,
              'total_net_salary': 0.0,
              'total_approved_advances': 0.0,
              'available_advance': 0.0,
            });
          }
        }
        
        setState((){ 
          _rows = list; 
          _loading = false;
          _error = list.isEmpty ? 'لا توجد بيانات موظفين' : null;
        });
        return;
      }
      
      // إذا في بيانات في الـ view
      print('✅ [Salaries] Processing ${salariesResp.length} salary records');
      
      // جلب بيانات الموظفين
      final employeesResp = await client
          .from('employees')
          .select('id, full_name, role, branch');
      
      print('👥 [Salaries] Found ${(employeesResp as List).length} employees');
      
      final employeeMap = <String, Map<String,dynamic>>{};
      for (final e in (employeesResp as List)) {
        employeeMap[e['id']] = e;
      }
      
      final List<Map<String,dynamic>> list = [];
      
      // عرض كل البيانات من الـ view مع جلب period earnings لكل موظف
      for (final row in salariesResp) {
        final empId = row['employee_id'] as String?;
        if (empId == null || empId.isEmpty) continue;
        
        final emp = employeeMap[empId];
        
        // جلب period earnings من الـ function (نفس المربع الأزرق)
        double periodEarnings = 0.0;
        try {
          final periodResult = await SupabaseFunctionClient.post('employee-period-earnings', {
            'employee_id': empId,
          });
          
          if ((periodResult ?? {})['success'] == true) {
            final totals = (periodResult ?? {})['totals'] as Map<String, dynamic>?;
            periodEarnings = (totals?['net'] as num?)?.toDouble() ?? 0.0;
          }
        } catch (e) {
          print('⚠️ [Salaries] Failed to load period earnings for $empId: $e');
          // استخدام current_salary كـ fallback
          periodEarnings = (row['current_salary'] as num?)?.toDouble() ?? 0.0;
        }
        
        final map = {
          'id': empId,
          'full_name': emp?['full_name'] ?? 'غير معروف',
          'role': emp?['role'] ?? '—',
          'branch': emp?['branch'] ?? '—',
          'current_salary': periodEarnings, // استخدام period earnings بدلاً من current_salary
          'total_net_salary': (row['total_net_salary'] as num?)?.toDouble() ?? 0.0,
          'total_approved_advances': (row['total_approved_advances'] as num?)?.toDouble() ?? 0.0,
          'available_advance': (row['available_advance_30_percent'] as num?)?.toDouble() ?? 0.0,
        };
        list.add(map);
      }
      
      print('✅ [Salaries] Processed ${list.length} records successfully');
      
      setState((){ 
        _rows = list; 
        _loading = false;
        _error = null;
      });
    } catch(e, stackTrace){ 
      print('❌ [Salaries] Error: $e');
      print('❌ [Salaries] StackTrace: $stackTrace');
      setState((){ 
        _error = 'خطأ في تحميل البيانات: $e'; 
        _loading = false; 
      }); 
    }
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(
        title: const Text('رواتب الموظفين'),
        backgroundColor: AppColors.primaryOrange,
        foregroundColor: Colors.white,
        actions:[IconButton(onPressed:_load, icon: const Icon(Icons.refresh))],
      ),
      body: _loading? const Center(child: CircularProgressIndicator()): _error!=null? _errorView(): _tableView(),
    );
  }

  Widget _errorView(){ return Center(child: Column(mainAxisSize: MainAxisSize.min, children:[ const Icon(Icons.error_outline,size:56,color:AppColors.error), const SizedBox(height:12), Text(_error!), ElevatedButton(onPressed:_load, child: const Text('إعادة المحاولة')) ])); }

  Widget _tableView(){
    if (_rows.isEmpty){ 
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Text('لا يوجد بيانات رواتب', style: TextStyle(fontSize: 16)),
        ),
      ); 
    }
    return RefreshIndicator(
      onRefresh: () async { await _load(); },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // جدول بسيط بعمودين
          Card(
            elevation: 2,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(AppColors.primaryOrange.withOpacity(.1)),
              columns: const [
                DataColumn(
                  label: Text(
                    'الموظف',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'الراتب الحالي',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
              rows: _rows.map((r){
                return DataRow(
                  cells: [
                    DataCell(
                      InkWell(
                        onTap: () => _openPayrollReport(r['id'], r['full_name']),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            r['full_name'] ?? 'غير معروف',
                            style: const TextStyle(
                              color: AppColors.primaryOrange,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),
                    ),
                    DataCell(
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          _money(r['current_salary']),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Colors.green,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  void _openPayrollReport(String employeeId, String employeeName){
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EmployeePayrollReportPage(
          employeeId: employeeId,
          employeeName: employeeName,
        ),
      ),
    );
  }

  String _money(dynamic v){ final numVal = (v is num)? v.toDouble() : double.tryParse(v.toString()) ?? 0; return numVal.toStringAsFixed(2)+' ج.م'; }
}
