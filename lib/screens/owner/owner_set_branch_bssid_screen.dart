import 'package:flutter/material.dart';
import 'package:heartbeat/services/owner_api_service.dart';
import 'package:heartbeat/services/wifi_service.dart';
import 'package:heartbeat/theme/app_colors.dart';

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
  String? _scannedBssid;
  bool _isScanning = false;
  bool _isSaving = false;
  String? _scanError;

  Future<void> _scanBssid() async {
    setState(() {
      _isScanning = true;
      _scannedBssid = null;
      _scanError = null;
    });
    try {
      // Use the new WifiService to get validated BSSID
      final bssid = await WifiService.getCurrentWifiBssidValidated();
      setState(() {
        _scannedBssid = bssid;
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
    if (_scannedBssid == null) return;

    setState(() => _isSaving = true);
    try {
      await OwnerApiService.updateBranchBssid(widget.branchId, _scannedBssid!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ تم حفظ BSSID بنجاح'),
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
            if (_scannedBssid != null) ...[
              const Divider(height: 30),
              const Text(
                'الـ BSSID المقروء:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              SelectableText(
                _scannedBssid!,
                style: const TextStyle(fontSize: 18, fontFamily: 'monospace', color: Colors.green),
                textAlign: TextAlign.center,
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
                    : const Text('حفظ هذا الـ BSSID للفرع'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}