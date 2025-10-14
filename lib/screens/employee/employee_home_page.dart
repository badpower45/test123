import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';
import '../../services/background_pulse_service.dart';
import '../../constants/restaurant_config.dart';

class EmployeeHomePage extends StatefulWidget {
  const EmployeeHomePage({super.key, required this.employeeId});

  final String employeeId;

  @override
  State<EmployeeHomePage> createState() => _EmployeeHomePageState();
}

class _EmployeeHomePageState extends State<EmployeeHomePage> {
  bool _checkedIn = false;
  bool _isProcessing = false;
  DateTime? _checkInTime;
  Duration _elapsed = Duration.zero;
  Timer? _timer;
  int _pulseCount = 0;
  bool _isOnline = true;
  StreamSubscription<Map<String, dynamic>?>? _statusSubscription;

  @override
  void initState() {
    super.initState();
    _statusSubscription = BackgroundPulseService.statusStream().listen((event) {
      if (!mounted || event == null) return;
      
      setState(() {
        _isOnline = event['isOnline'] != false;
        _pulseCount = (event['pulseCounter'] as num?)?.toInt() ?? _pulseCount;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _statusSubscription?.cancel();
    super.dispose();
  }

  Future<void> _handleCheckIn() async {
    setState(() => _isProcessing = true);

    try {
      await BackgroundPulseService.start(
        PulseConfig(
          employeeId: widget.employeeId,
          restaurantLat: RestaurantConfig.latitude,
          restaurantLon: RestaurantConfig.longitude,
          radiusInMeters: RestaurantConfig.allowedRadiusInMeters,
          enforceLocation: RestaurantConfig.enforceLocation,
        ),
      );

      setState(() {
        _checkedIn = true;
        _checkInTime = DateTime.now();
        _elapsed = Duration.zero;
        _isProcessing = false;
      });
      
      _startTimer();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.success,
          content: Text(
            'تم تسجيل الحضور بنجاح - ${_formatTime(DateTime.now())}',
            style: GoogleFonts.ibmPlexSansArabic(color: Colors.white),
            textDirection: TextDirection.rtl,
          ),
        ),
      );
    } catch (e) {
      setState(() => _isProcessing = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.danger,
          content: Text(
            'فشل تسجيل الحضور: ${e.toString()}',
            style: GoogleFonts.ibmPlexSansArabic(color: Colors.white),
            textDirection: TextDirection.rtl,
          ),
        ),
      );
    }
  }

  Future<void> _handleCheckOut() async {
    setState(() => _isProcessing = true);

    try {
      await BackgroundPulseService.stop();
      _timer?.cancel();

      setState(() {
        _checkedIn = false;
        _elapsed = Duration.zero;
        _checkInTime = null;
        _isProcessing = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.success,
          content: Text(
            'تم تسجيل الانصراف بنجاح',
            style: GoogleFonts.ibmPlexSansArabic(color: Colors.white),
            textDirection: TextDirection.rtl,
          ),
        ),
      );
    } catch (e) {
      setState(() => _isProcessing = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.danger,
          content: Text(
            'فشل تسجيل الانصراف: ${e.toString()}',
            style: GoogleFonts.ibmPlexSansArabic(color: Colors.white),
            textDirection: TextDirection.rtl,
          ),
        ),
      );
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _checkInTime == null) return;
      setState(() {
        _elapsed = DateTime.now().difference(_checkInTime!);
      });
    });
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildStatusCard(),
              const SizedBox(height: 20),
              _buildTimerCard(),
              const SizedBox(height: 20),
              _buildActionButton(),
              const SizedBox(height: 16),
              if (_checkedIn) _buildAttendanceRequestButton(),
              const SizedBox(height: 20),
              _buildStatsRow(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _checkedIn
              ? [AppColors.success, AppColors.success.withOpacity(0.8)]
              : [Colors.grey.shade400, Colors.grey.shade500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (_checkedIn ? AppColors.success : Colors.grey).withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(
            _checkedIn ? Icons.check_circle : Icons.access_time,
            color: Colors.white,
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            _checkedIn ? 'أنت قيد العمل' : 'أنت خارج العمل',
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textDirection: TextDirection.rtl,
          ),
          if (_checkedIn && _checkInTime != null) ...[
            const SizedBox(height: 8),
            Text(
              'بدأت الساعة ${_formatTime(_checkInTime!)}',
              style: GoogleFonts.ibmPlexSansArabic(
                fontSize: 16,
                color: Colors.white.withOpacity(0.9),
              ),
              textDirection: TextDirection.rtl,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimerCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            'مدة العمل الحالية',
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 16,
              color: Colors.grey.shade600,
            ),
            textDirection: TextDirection.rtl,
          ),
          const SizedBox(height: 16),
          Text(
            _formatDuration(_elapsed),
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: _checkedIn ? AppColors.primaryOrange : Colors.grey.shade400,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton() {
    return ElevatedButton(
      onPressed: _isProcessing
          ? null
          : (_checkedIn ? _handleCheckOut : _handleCheckIn),
      style: ElevatedButton.styleFrom(
        backgroundColor: _checkedIn ? AppColors.danger : AppColors.success,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 0,
      ),
      child: _isProcessing
          ? const SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _checkedIn ? Icons.logout : Icons.login,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  _checkedIn ? 'تسجيل الانصراف' : 'تسجيل الحضور',
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  textDirection: TextDirection.rtl,
                ),
              ],
            ),
    );
  }

  Widget _buildAttendanceRequestButton() {
    return OutlinedButton.icon(
      onPressed: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'سيتم إضافة نموذج طلب الحضور قريباً',
              style: GoogleFonts.ibmPlexSansArabic(),
              textDirection: TextDirection.rtl,
            ),
          ),
        );
      },
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        side: BorderSide(color: AppColors.primaryOrange),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      icon: const Icon(Icons.assignment_late, color: AppColors.primaryOrange),
      label: Text(
        'طلب حضور (نسيت التسجيل)',
        style: GoogleFonts.ibmPlexSansArabic(
          fontSize: 16,
          color: AppColors.primaryOrange,
          fontWeight: FontWeight.w600,
        ),
        textDirection: TextDirection.rtl,
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            icon: Icons.repeat,
            label: 'النبضات اليوم',
            value: _pulseCount.toString(),
            color: AppColors.primaryOrange,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            icon: _isOnline ? Icons.wifi : Icons.wifi_off,
            label: 'الحالة',
            value: _isOnline ? 'متصل' : 'أوفلاين',
            color: _isOnline ? Colors.blue : Colors.orange,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
            textDirection: TextDirection.rtl,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
