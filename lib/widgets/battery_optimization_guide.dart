import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/aggressive_keep_alive_service.dart';
import '../services/app_logger.dart';

/// 🔋 Battery Optimization Guide Screen
/// 
/// Shows device-specific instructions for disabling battery optimization
/// to ensure pulses work in background on old devices like Realme 6, Galaxy A12, etc.
class BatteryOptimizationGuide extends StatefulWidget {
  final String? employeeId;
  final VoidCallback? onComplete;

  const BatteryOptimizationGuide({
    super.key,
    this.employeeId,
    this.onComplete,
  });

  @override
  State<BatteryOptimizationGuide> createState() => _BatteryOptimizationGuideState();
}

class _BatteryOptimizationGuideState extends State<BatteryOptimizationGuide> {
  final _keepAliveService = AggressiveKeepAliveService();
  Map<String, dynamic> _deviceInfo = {};
  String _guide = '';
  bool _isLoading = true;
  bool _batteryOptimizationDisabled = false;

  @override
  void initState() {
    super.initState();
    _loadDeviceInfo();
  }

  Future<void> _loadDeviceInfo() async {
    await _keepAliveService.initialize();
    
    setState(() {
      _deviceInfo = _keepAliveService.getDeviceInfo();
      _guide = _keepAliveService.getBatteryOptimizationGuide();
      _isLoading = false;
    });
    
    // Check current battery optimization status
    await _checkBatteryOptimizationStatus();
  }

  Future<void> _checkBatteryOptimizationStatus() async {
    final status = await Permission.ignoreBatteryOptimizations.status;
    setState(() {
      _batteryOptimizationDisabled = status.isGranted;
    });
  }

  Future<void> _requestBatteryOptimization() async {
    try {
      final status = await Permission.ignoreBatteryOptimizations.request();
      
      if (status.isGranted) {
        setState(() {
          _batteryOptimizationDisabled = true;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم تعطيل تحسين البطارية للتطبيق'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (status.isPermanentlyDenied) {
        // Open app settings
        await openAppSettings();
      }
    } catch (e) {
      AppLogger.instance.log('Error requesting battery optimization', level: AppLogger.error, tag: 'BatteryGuide', error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إعدادات البطارية'),
        centerTitle: true,
        backgroundColor: Colors.orange.shade700,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Warning Card
                  Card(
                    color: Colors.orange.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 48,
                            color: Colors.orange.shade700,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'إعدادات مهمة للتتبع في الخلفية',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade900,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'لضمان عمل التطبيق بشكل صحيح وتسجيل النبضات في الخلفية، يجب تعطيل تحسين البطارية للتطبيق.',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.orange.shade800,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Device Info Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.phone_android, color: Colors.blue.shade700),
                              const SizedBox(width: 8),
                              const Text(
                                'معلومات الجهاز',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildInfoRow('الشركة المصنعة', _deviceInfo['manufacturer']?.toString().toUpperCase() ?? 'غير معروف'),
                          _buildInfoRow('الموديل', _deviceInfo['model'] ?? 'غير معروف'),
                          _buildInfoRow('إصدار Android', 'API ${_deviceInfo['androidSdk'] ?? 'غير معروف'}'),
                          _buildInfoRow(
                            'الوضع العدواني',
                            _deviceInfo['aggressiveMode'] == true ? 'مفعّل ✅' : 'معطل',
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Battery Optimization Status
                  Card(
                    color: _batteryOptimizationDisabled 
                        ? Colors.green.shade50 
                        : Colors.red.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Icon(
                            _batteryOptimizationDisabled 
                                ? Icons.check_circle 
                                : Icons.error,
                            size: 40,
                            color: _batteryOptimizationDisabled 
                                ? Colors.green 
                                : Colors.red,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _batteryOptimizationDisabled
                                ? 'تحسين البطارية معطل ✅'
                                : 'تحسين البطارية مفعل ⚠️',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: _batteryOptimizationDisabled 
                                  ? Colors.green.shade700 
                                  : Colors.red.shade700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (!_batteryOptimizationDisabled)
                            ElevatedButton.icon(
                              onPressed: _requestBatteryOptimization,
                              icon: const Icon(Icons.battery_alert),
                              label: const Text('تعطيل تحسين البطارية'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange.shade700,
                                foregroundColor: Colors.white,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Device-specific Guide
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.settings, color: Colors.blue.shade700),
                              const SizedBox(width: 8),
                              const Text(
                                'خطوات إضافية لجهازك',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _guide,
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.6,
                              ),
                              textDirection: TextDirection.rtl,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Open Settings Button
                  ElevatedButton.icon(
                    onPressed: () async {
                      await openAppSettings();
                    },
                    icon: const Icon(Icons.settings),
                    label: const Text('فتح إعدادات التطبيق'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // Done Button
                  OutlinedButton(
                    onPressed: () {
                      widget.onComplete?.call();
                      Navigator.of(context).pop();
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('تم'),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Tips Section
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.lightbulb, color: Colors.blue.shade700),
                            const SizedBox(width: 8),
                            Text(
                              'نصائح مهمة',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildTip('لا تغلق التطبيق من قائمة التطبيقات الأخيرة'),
                        _buildTip('اترك الإشعار الدائم ظاهراً'),
                        _buildTip('تأكد من اتصالك بالإنترنت'),
                        _buildTip('إذا لم تظهر النبضات، أعد تشغيل الهاتف'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade600,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTip(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle, size: 18, color: Colors.green.shade600),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: Colors.blue.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dialog version of the guide for quick display
class BatteryOptimizationDialog extends StatelessWidget {
  final VoidCallback? onSettings;
  final VoidCallback? onDismiss;

  const BatteryOptimizationDialog({
    super.key,
    this.onSettings,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.battery_alert, color: Colors.orange.shade700),
          const SizedBox(width: 8),
          const Text('إعدادات البطارية'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'لضمان تسجيل النبضات في الخلفية، يُنصح بتعطيل تحسين البطارية للتطبيق.',
            style: TextStyle(color: Colors.grey.shade700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.yellow.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.yellow.shade300),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'هذا مهم جداً للأجهزة القديمة!',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            onDismiss?.call();
            Navigator.of(context).pop();
          },
          child: const Text('لاحقاً'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop();
            onSettings?.call();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange.shade700,
            foregroundColor: Colors.white,
          ),
          child: const Text('فتح الإعدادات'),
        ),
      ],
    );
  }
}
