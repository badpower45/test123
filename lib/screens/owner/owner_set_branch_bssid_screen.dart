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
  List<String> _bssidList = [];
  bool _isScanning = false;
  bool _isSaving = false;
  bool _isLoading = true;
  String? _scanError;
  final TextEditingController _newBssidController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadBssids();
  }

  @override
  void dispose() {
    _newBssidController.dispose();
    super.dispose();
  }

  Future<void> _loadBssids() async {
    setState(() => _isLoading = true);
    try {
      final bssids = await OwnerApiService.getBranchBssids(widget.branchId);
      setState(() {
        _bssidList = bssids;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحميل BSSIDs: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _scanAndAddBssid() async {
    setState(() {
      _isScanning = true;
      _scanError = null;
    });
    try {
      // Use the WiFiService to get validated BSSID
      final bssid = await WiFiService.getCurrentWifiBssidValidated();

      // Check if already exists
      if (_bssidList.contains(bssid)) {
        setState(() {
          _scanError = 'هذا الـ BSSID موجود بالفعل';
        });
        return;
      }

      // Add to backend
      await OwnerApiService.addBranchBssid(widget.branchId, bssid);

      // Reload list
      await _loadBssids();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم إضافة BSSID: $bssid'),
            backgroundColor: Colors.green,
          ),
        );
      }
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

  Future<void> _removeBssid(String bssid) async {
    try {
      await OwnerApiService.removeBranchBssid(widget.branchId, bssid);
      await _loadBssids();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حذف BSSID بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
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
    }
  }

  Future<void> _addManualBssid() async {
    final bssid = _newBssidController.text.trim().toUpperCase();

    if (bssid.isEmpty) return;

    if (!WiFiService.isValidBssidFormat(bssid)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('صيغة BSSID غير صحيحة'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_bssidList.contains(bssid)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('هذا الـ BSSID موجود بالفعل'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      await OwnerApiService.addBranchBssid(widget.branchId, bssid);
      _newBssidController.clear();
      await _loadBssids();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم إضافة BSSID: $bssid'),
            backgroundColor: Colors.green,
          ),
        );
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
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('ضبط Wi-Fi للفرع: ${widget.branchName}'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'إدارة BSSIDs المعتمدة للفرع',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'يمكنك إضافة عدة BSSIDs لدعم الراوتر Dual-band (2.4GHz و 5GHz)',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 24),

                  // Scan button
                  ElevatedButton.icon(
                    onPressed: _isScanning ? null : _scanAndAddBssid,
                    icon: _isScanning
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.wifi_find),
                    label: const Text('مسح وإضافة الشبكة الحالية'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (_scanError != null)
                    Text(
                      _scanError!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),

                  const Divider(height: 30),

                  // Manual entry
                  const Text(
                    'أو أدخل BSSID يدوياً:',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _newBssidController,
                          decoration: const InputDecoration(
                            hintText: 'AA:BB:CC:DD:EE:FF',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                          textCapitalization: TextCapitalization.characters,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _addManualBssid,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        ),
                        child: const Text('إضافة'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 12),

                  // BSSIDs list
                  Text(
                    'BSSIDs المسجلة (${_bssidList.length}):',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),

                  Expanded(
                    child: _bssidList.isEmpty
                        ? const Center(
                            child: Text(
                              'لا توجد BSSIDs مسجلة بعد\nقم بمسح الشبكة أو إضافتها يدوياً',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey, fontSize: 14),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _bssidList.length,
                            itemBuilder: (context, index) {
                              final bssid = _bssidList[index];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: const Icon(Icons.wifi, color: Colors.green),
                                  title: Text(
                                    bssid,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text('BSSID ${index + 1}'),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: const Text('تأكيد الحذف'),
                                          content: Text('هل تريد حذف BSSID:\n$bssid'),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.of(context).pop(false),
                                              child: const Text('إلغاء'),
                                            ),
                                            TextButton(
                                              onPressed: () => Navigator.of(context).pop(true),
                                              child: const Text('حذف', style: TextStyle(color: Colors.red)),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirm == true) {
                                        _removeBssid(bssid);
                                      }
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}