import 'package:flutter/material.dart';
import 'package:at_app/services/native_location_service.dart';
import 'package:at_app/services/native_pulse_service.dart';

/// 🧪 صفحة اختبار Native Services
/// 
/// استخدم هذه الصفحة لاختبار:
/// 1. Native GPS (FastGPSModule.kt)
/// 2. Native Pulse Service (PersistentPulseService.kt)
class NativeServicesTestPage extends StatefulWidget {
  const NativeServicesTestPage({Key? key}) : super(key: key);

  @override
  State<NativeServicesTestPage> createState() => _NativeServicesTestPageState();
}

class _NativeServicesTestPageState extends State<NativeServicesTestPage> {
  String _gpsResult = 'اضغط لاختبار GPS';
  String _pulseResult = 'اضغط لبدء النبضات';
  bool _isLoading = false;
  bool _serviceRunning = false;

  @override
  void initState() {
    super.initState();
    _checkServiceStatus();
  }

  Future<void> _checkServiceStatus() async {
    final isRunning = await NativePulseService.isServiceRunning();
    setState(() {
      _serviceRunning = isRunning;
      _pulseResult = isRunning ? '🟢 النبضات تعمل' : '⚪ النبضات متوقفة';
    });
  }

  Future<void> _testNativeGPS() async {
    setState(() {
      _isLoading = true;
      _gpsResult = '⏳ جاري الحصول على الموقع...';
    });

    final stopwatch = Stopwatch()..start();
    final position = await NativeLocationService.getCurrentLocation();
    stopwatch.stop();

    setState(() {
      _isLoading = false;
      if (position != null) {
        _gpsResult = '''
✅ نجح! الوقت: ${stopwatch.elapsedMilliseconds}ms

📍 الموقع:
   Lat: ${position.latitude.toStringAsFixed(6)}
   Lng: ${position.longitude.toStringAsFixed(6)}
   
📏 الدقة: ±${position.accuracy.toStringAsFixed(1)}م

⏱️ الوقت: ${position.timestamp}

🚀 السرعة: ${stopwatch.elapsedMilliseconds < 5000 ? 'ممتاز!' : 'بطيء'}
        ''';
      } else {
        _gpsResult = '❌ فشل الحصول على الموقع\nالوقت: ${stopwatch.elapsedMilliseconds}ms';
      }
    });
  }

  Future<void> _startPulseService() async {
    setState(() {
      _isLoading = true;
      _pulseResult = '⏳ جاري بدء النبضات...';
    });

    final success = await NativePulseService.startPersistentService(
      employeeId: 'test_emp_001',
      attendanceId: 'test_att_001',
      branchId: 'test_branch_001',
      intervalMinutes: 1, // نبضة كل دقيقة للاختبار
    );

    await _checkServiceStatus();

    setState(() {
      _isLoading = false;
      if (success) {
        _pulseResult = '''
✅ بدأت النبضات بنجاح!

📋 المعلومات:
   Employee: test_emp_001
   Attendance: test_att_001
   الفاصل: دقيقة واحدة
   
🔥 الخدمة تعمل في الخلفية

📱 يمكنك إغلاق التطبيق - النبضات ستستمر!
        ''';
      } else {
        _pulseResult = '❌ فشل بدء النبضات\n(ربما Android غير مدعوم)';
      }
    });
  }

  Future<void> _stopPulseService() async {
    setState(() {
      _isLoading = true;
      _pulseResult = '⏳ جاري إيقاف النبضات...';
    });

    final success = await NativePulseService.stopPersistentService();

    await _checkServiceStatus();

    setState(() {
      _isLoading = false;
      if (success) {
        _pulseResult = '⚪ تم إيقاف النبضات';
      } else {
        _pulseResult = '❌ فشل إيقاف النبضات';
      }
    });
  }

  Future<void> _getPulseStats() async {
    setState(() {
      _isLoading = true;
      _pulseResult = '⏳ جاري جلب الإحصائيات...';
    });

    final stats = await NativePulseService.getPulseStats();

    setState(() {
      _isLoading = false;
      if (stats != null) {
        final pulseCount = stats['pulse_count'] as int;
        final lastPulseTime = stats['last_pulse_time'] as int;
        final uptime = stats['service_uptime'] as int;
        
        final lastPulse = DateTime.fromMillisecondsSinceEpoch(lastPulseTime);
        final uptimeMin = uptime ~/ 60000;

        _pulseResult = '''
📊 إحصائيات النبضات:

💓 عدد النبضات: $pulseCount
⏰ آخر نبضة: ${lastPulse.hour}:${lastPulse.minute}:${lastPulse.second}
⏱️ وقت التشغيل: $uptimeMin دقيقة
        ''';
      } else {
        _pulseResult = '❌ لا توجد إحصائيات (الخدمة متوقفة؟)';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('اختبار Native Services'),
        backgroundColor: Colors.blue,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // GPS Test Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.location_on, color: Colors.blue, size: 32),
                        const SizedBox(width: 8),
                        const Text(
                          'اختبار Native GPS',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _gpsResult,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _testNativeGPS,
                      icon: const Icon(Icons.gps_fixed),
                      label: const Text('اختبار GPS'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Pulse Service Test Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _serviceRunning ? Icons.favorite : Icons.favorite_border,
                          color: _serviceRunning ? Colors.red : Colors.grey,
                          size: 32,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'خدمة النبضات',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _pulseResult,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isLoading || _serviceRunning ? null : _startPulseService,
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('بدء'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              minimumSize: const Size(0, 48),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isLoading || !_serviceRunning ? null : _stopPulseService,
                            icon: const Icon(Icons.stop),
                            label: const Text('إيقاف'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              minimumSize: const Size(0, 48),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _getPulseStats,
                      icon: const Icon(Icons.bar_chart),
                      label: const Text('الإحصائيات'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Info Card
            Card(
              color: Colors.amber[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      '💡 نصائح الاختبار',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text('✅ GPS يجب أن يستجيب في < 5 ثوانٍ'),
                    Text('✅ أغلق التطبيق بعد بدء النبضات - يجب أن تستمر'),
                    Text('✅ راقب Logcat لرؤية "💓 Sending pulse"'),
                    Text('✅ Force Stop من الإعدادات - يجب أن تعود الخدمة'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
