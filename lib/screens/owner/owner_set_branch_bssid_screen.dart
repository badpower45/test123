import 'package:flutter/material.dart';
import '../../services/owner_api_service.dart';
import '../../services/wifi_service.dart';
import '../../theme/app_colors.dart';

class OwnerSetBranchBssidScreen extends StatefulWidget {
  final String branchId;
  final String branchName;

  const OwnerSetBranchBssidScreen({
    super.key,
    required this.branchId,
    required this.branchName,
  });

  @override
  State<OwnerSetBranchBssidScreen> createState() => _OwnerSetBranchBssidScreenState();
}

class _OwnerSetBranchBssidScreenState extends State<OwnerSetBranchBssidScreen> {
  String? _scannedBssid1;
  String? _scannedBssid2;
  bool _isScanning = false;
  bool _isSaving = false;
  String? _scanError;
  final TextEditingController _bssid1Controller = TextEditingController();
  final TextEditingController _bssid2Controller = TextEditingController();

  @override
  void dispose() {
    _bssid1Controller.dispose();
    _bssid2Controller.dispose();
    super.dispose();
  }

  Future<void> _scanBssid() async {
    setState(() {
      _isScanning = true;
      _scannedBssid1 = null;
      _scannedBssid2 = null;
      _scanError = null;
    });
    try {
      // Use the WiFiService to get validated BSSID
      final bssid = await WiFiService.getCurrentWifiBssidValidated();
      setState(() {
        _scannedBssid1 = bssid;
        _bssid1Controller.text = bssid;
      });
    } catch (e) {
      setState(() {
        _scanError = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  Future<void> _saveBssid() async {
    if (_bssid1Controller.text.isEmpty) return;

    setState(() => _isSaving = true);
    try {
      await OwnerApiService.updateBranchBssid(
        widget.branchId,
        _bssid1Controller.text.trim().toUpperCase(),
        _bssid2Controller.text.isNotEmpty ? _bssid2Controller.text.trim().toUpperCase() : null,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ تم حفظ BSSIDs بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(); // Return to previous screen
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('ضبط Wi-Fi للفرع: ${widget.branchName}'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'تأكد من اتصالك بشبكة الواي فاي الصحيحة الخاصة بهذا الفرع أولاً.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isScanning ? null : _scanBssid,
              icon: _isScanning
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.wifi_find),
              label: const Text('قراءة BSSID الشبكة الحالية'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 20),
            if (_scanError != null)
              Text(
                'خطأ أثناء القراءة: $_scanError',
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            const Divider(height: 30),
            const Text(
              'BSSID 1 (إجباري):',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _bssid1Controller,
              decoration: const InputDecoration(
                hintText: 'أدخل BSSID الأول أو اضغط على قراءة',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 16),
            const Text(
              'BSSID 2 (اختياري):',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _bssid2Controller,
              decoration: const InputDecoration(
                hintText: 'أدخل BSSID الثاني إذا كان موجوداً',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isSaving ? null : _saveBssid,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isSaving
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('حفظ BSSIDs للفرع'),
            ),
          ],
        ),
      ),
    );
  }
}