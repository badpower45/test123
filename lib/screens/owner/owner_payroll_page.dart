import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/payroll_service.dart';
import 'owner_branch_payroll_details_page.dart';

class OwnerPayrollPage extends StatefulWidget {
  const OwnerPayrollPage({super.key});

  @override
  State<OwnerPayrollPage> createState() => _OwnerPayrollPageState();
}

class _OwnerPayrollPageState extends State<OwnerPayrollPage> {
  final PayrollService _payrollService = PayrollService();
  List<Map<String, dynamic>> _branches = [];
  bool _isLoading = true;
  DateTime _selectedMonth = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadBranchPayrolls();
  }

  Future<void> _loadBranchPayrolls() async {
    setState(() => _isLoading = true);
    
    final branches = await _payrollService.getBranchPayrollSummary();
    
    setState(() {
      _branches = branches;
      _isLoading = false;
    });
  }

  Future<void> _markBranchAsPaid(String cycleId, String branchName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الدفع'),
        content: Text('هل أنت متأكد من دفع مرتبات فرع $branchName؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
            ),
            child: const Text('نعم، تم الدفع'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await _payrollService.markBranchPayrollPaid(
        cycleId: cycleId,
        paidBy: 'current_user_id', // Replace with actual user ID
      );

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم تسجيل الدفع بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
        _loadBranchPayrolls();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ فشل تسجيل الدفع'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('المرتبات'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadBranchPayrolls,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _branches.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.money_off, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'لا توجد مرتبات مستحقة حالياً',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadBranchPayrolls,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _branches.length,
                    itemBuilder: (context, index) {
                      final branch = _branches[index];
                      final branchData = branch['branches'] as Map<String, dynamic>;
                      final branchName = branchData['name'] as String;
                      final cycleId = branch['id'] as String;
                      final totalAmount = (branch['total_amount'] as num?)?.toDouble() ?? 0;
                      final status = branch['status'] as String;
                      final isPaid = status == 'paid';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) {
                                DateTime startDate;
                                DateTime endDate;
                                try {
                                  startDate = DateTime.parse(branch['start_date']?.toString() ?? '');
                                } catch (e) {
                                  startDate = DateTime.now();
                                }
                                try {
                                  endDate = DateTime.parse(branch['end_date']?.toString() ?? '');
                                } catch (e) {
                                  endDate = DateTime.now();
                                }
                                return OwnerBranchPayrollDetailsPage(
                                  cycleId: cycleId,
                                  branchName: branchName,
                                  startDate: startDate,
                                  endDate: endDate,
                                );
                              },
                              ),
                            ).then((_) => _loadBranchPayrolls());
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            branchName,
                                            style: const TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            branchData['location'] as String? ?? '',
                                            style: const TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isPaid ? Colors.green : Colors.orange,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        isPaid ? 'مدفوع' : 'معلق',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 24),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'الفترة',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Builder(builder: (context) {
                                          String startStr = '-';
                                          String endStr = '-';
                                          try {
                                            startStr = DateFormat('dd/MM/yyyy').format(DateTime.parse(branch['start_date']?.toString() ?? ''));
                                          } catch (e) { /* ignore */ }
                                          try {
                                            endStr = DateFormat('dd/MM/yyyy').format(DateTime.parse(branch['end_date']?.toString() ?? ''));
                                          } catch (e) { /* ignore */ }
                                          return Text(
                                            '$startStr - $endStr',
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          );
                                        }),
                                      ],
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        const Text(
                                          'الإجمالي المستحق',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${totalAmount.toStringAsFixed(2)} ج.م',
                                          style: const TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.deepPurple,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                if (!isPaid) ...[
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      onPressed: () => _markBranchAsPaid(cycleId, branchName),
                                      icon: const Icon(Icons.check_circle),
                                      label: const Text('تم الدفع'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                                if (isPaid) ...[
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      const Icon(Icons.check_circle, color: Colors.green, size: 16),
                                      const SizedBox(width: 8),
                                      Builder(builder: (context) {
                                        String paidAtStr = '';
                                        try {
                                          paidAtStr = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(branch['paid_at']?.toString() ?? ''));
                                        } catch (e) {
                                          paidAtStr = '-';
                                        }
                                        return Text(
                                          'تم الدفع في $paidAtStr',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.green,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
