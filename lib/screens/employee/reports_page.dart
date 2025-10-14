import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';
import '../../models/attendance_report.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key, required this.employeeId});

  final String employeeId;

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  bool _isLoading = false;
  AttendanceReport? _report;

  bool get _isDay1or16 {
    final now = DateTime.now();
    return now.day == 1 || now.day == 16;
  }

  Future<void> _loadReport(String period) async {
    setState(() => _isLoading = true);

    await Future.delayed(const Duration(seconds: 1));

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'سيتم تحميل التقرير من الـ API قريباً',
          style: GoogleFonts.ibmPlexSansArabic(),
          textDirection: TextDirection.rtl,
        ),
      ),
    );

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final daysUntilNext = now.day < 16
        ? 16 - now.day
        : DateTime(now.year, now.month + 1, 1).difference(now).inDays;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'تقرير الحضور',
          style: GoogleFonts.ibmPlexSansArabic(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _report == null
              ? _buildEmptyState(daysUntilNext)
              : _buildReportView(),
    );
  }

  Widget _buildEmptyState(int daysUntilNext) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primaryOrange, Color(0xFFFF9A56)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryOrange.withOpacity(0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                Icon(
                  _isDay1or16 ? Icons.description : Icons.lock_clock,
                  size: 64,
                  color: Colors.white,
                ),
                const SizedBox(height: 16),
                Text(
                  _isDay1or16
                      ? 'التقرير متاح الآن'
                      : 'التقرير غير متاح حالياً',
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  _isDay1or16
                      ? 'يمكنك الآن عرض تقرير الحضور والراتب'
                      : 'يمكنك عرض التقرير في يوم 1 أو يوم 16 من كل شهر',
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 16,
                    color: Colors.white.withOpacity(0.9),
                  ),
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.rtl,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (!_isDay1or16) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.calendar_month,
                    size: 48,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'متبقي $daysUntilNext يوم على التقرير التالي',
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                    textDirection: TextDirection.rtl,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'سيتم فتح التقرير تلقائياً في التاريخ المحدد',
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 14,
                      color: Colors.grey.shade500,
                    ),
                    textDirection: TextDirection.rtl,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
          _buildReportTypeCard(
            title: 'تقرير منتصف الشهر',
            subtitle: 'من 1 إلى 15 ${_getMonthName(DateTime.now().month)}',
            icon: Icons.calendar_view_month,
            color: Colors.blue,
            enabled: _isDay1or16 && DateTime.now().day == 16,
            onTap: () => _loadReport('mid-month'),
          ),
          const SizedBox(height: 12),
          _buildReportTypeCard(
            title: 'تقرير نهاية الشهر',
            subtitle: 'من 16 إلى آخر ${_getMonthName(DateTime.now().month)}',
            icon: Icons.calendar_today,
            color: Colors.purple,
            enabled: _isDay1or16 && DateTime.now().day == 1,
            onTap: () => _loadReport('full-month'),
          ),
        ],
      ),
    );
  }

  Widget _buildReportTypeCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: enabled ? color : Colors.grey.shade300,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: enabled ? Colors.black87 : Colors.grey.shade600,
                      ),
                      textDirection: TextDirection.rtl,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                      textDirection: TextDirection.rtl,
                    ),
                  ],
                ),
              ),
              if (enabled)
                Icon(Icons.arrow_forward_ios, color: color, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReportView() {
    if (_report == null) return const SizedBox();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSummaryCard(),
          const SizedBox(height: 16),
          _buildAttendanceTable(),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryOrange, Color(0xFFFF9A56)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            'ملخص الفترة',
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSummaryItem('ساعات العمل', '120', Icons.access_time),
              _buildSummaryItem('السلف', '500', Icons.attach_money),
              _buildSummaryItem('الخصومات', '0', Icons.money_off),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 28),
        const SizedBox(height: 8),
        Text(
          value,
          style: GoogleFonts.ibmPlexSansArabic(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.ibmPlexSansArabic(
            fontSize: 12,
            color: Colors.white.withOpacity(0.9),
          ),
        ),
      ],
    );
  }

  Widget _buildAttendanceTable() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'سجل الحضور التفصيلي',
              style: GoogleFonts.ibmPlexSansArabic(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textDirection: TextDirection.rtl,
            ),
          ),
          const Divider(height: 1),
          _buildTableHeader(),
          const Divider(height: 1),
          _buildTableRow('1 يناير', '09:00', '17:00', '8.0', '0', '0'),
          const Divider(height: 1),
          _buildTableRow('2 يناير', '09:15', '17:10', '7.9', '0', '0'),
          const Divider(height: 1),
          _buildTableRow('3 يناير', '09:00', '18:00', '9.0', '0', '0'),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      color: Colors.grey.shade50,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: _buildTableHeaderCell('التاريخ'),
          ),
          Expanded(child: _buildTableHeaderCell('الحضور')),
          Expanded(child: _buildTableHeaderCell('الانصراف')),
          Expanded(child: _buildTableHeaderCell('الساعات')),
          Expanded(child: _buildTableHeaderCell('سلف')),
          Expanded(child: _buildTableHeaderCell('خصم')),
        ],
      ),
    );
  }

  Widget _buildTableHeaderCell(String text) {
    return Text(
      text,
      style: GoogleFonts.ibmPlexSansArabic(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: Colors.grey.shade700,
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.rtl,
    );
  }

  Widget _buildTableRow(
    String date,
    String checkIn,
    String checkOut,
    String hours,
    String advance,
    String deduction,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: _buildTableCell(date, fontSize: 13, bold: true),
          ),
          Expanded(child: _buildTableCell(checkIn)),
          Expanded(child: _buildTableCell(checkOut)),
          Expanded(child: _buildTableCell(hours)),
          Expanded(
            child: _buildTableCell(
              advance,
              color: advance != '0' ? AppColors.primaryOrange : null,
            ),
          ),
          Expanded(
            child: _buildTableCell(
              deduction,
              color: deduction != '0' ? AppColors.danger : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableCell(
    String text, {
    double fontSize = 12,
    bool bold = false,
    Color? color,
  }) {
    return Text(
      text,
      style: GoogleFonts.ibmPlexSansArabic(
        fontSize: fontSize,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        color: color ?? Colors.grey.shade700,
      ),
      textAlign: TextAlign.center,
    );
  }

  String _getMonthName(int month) {
    const months = [
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر'
    ];
    return months[month - 1];
  }
}
