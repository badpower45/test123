import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/blv/blv_manager.dart';

/// Manager Dashboard - BLV Flags Page
/// صفحة عرض الـ Flags للمديرين
class BLVFlagsPage extends StatefulWidget {
  final String managerId;
  final String? branchId;

  const BLVFlagsPage({
    super.key,
    required this.managerId,
    this.branchId,
  });

  @override
  State<BLVFlagsPage> createState() => _BLVFlagsPageState();
}

class _BLVFlagsPageState extends State<BLVFlagsPage> {
  final _blvManager = BLVManager();
  
  List<Map<String, dynamic>> _flags = [];
  bool _isLoading = true;
  String _selectedSeverity = 'all';
  
  @override
  void initState() {
    super.initState();
    _loadFlags();
  }
  
  Future<void> _loadFlags() async {
    setState(() => _isLoading = true);
    
    try {
      final flags = await _blvManager.fetchAllFlags(
        branchId: widget.branchId,
        severity: _selectedSeverity == 'all' ? null : _selectedSeverity,
      );
      
      setState(() {
        _flags = flags;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading flags: $e');
      setState(() => _isLoading = false);
    }
  }
  
  Future<void> _resolveFlag(String flagId, String employeeName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الموافقة'),
        content: Text('هل تريد الموافقة على النشاط لـ $employeeName؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('موافقة'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      final success = await _blvManager.resolveFlag(
        flagId,
        widget.managerId,
        resolution: 'Approved by manager',
      );
      
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ تم الموافقة بنجاح')),
        );
        _loadFlags(); // Reload
      }
    }
  }
  
  Color _getSeverityColor(String severity) {
    switch (severity) {
      case 'critical':
        return Colors.red;
      case 'high':
        return Colors.orange;
      case 'medium':
        return Colors.yellow.shade700;
      case 'low':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }
  
  IconData _getFlagTypeIcon(String flagType) {
    switch (flagType) {
      case 'NoMotion':
        return Icons.sensors_off;
      case 'PassiveAudio':
        return Icons.volume_off;
      case 'AnomalousWiFi':
        return Icons.wifi_off;
      case 'HeartbeatMiss':
        return Icons.favorite_border;
      case 'LowPresenceScore':
        return Icons.location_off;
      default:
        return Icons.flag;
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('التنبيهات والنشاط المشبوه'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadFlags,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter chips
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('الكل', 'all'),
                  const SizedBox(width: 8),
                  _buildFilterChip('حرج', 'critical'),
                  const SizedBox(width: 8),
                  _buildFilterChip('عالي', 'high'),
                  const SizedBox(width: 8),
                  _buildFilterChip('متوسط', 'medium'),
                  const SizedBox(width: 8),
                  _buildFilterChip('منخفض', 'low'),
                ],
              ),
            ),
          ),
          
          // Flags list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _flags.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        itemCount: _flags.length,
                        itemBuilder: (context, index) {
                          final flag = _flags[index];
                          return _buildFlagCard(flag);
                        },
                      ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedSeverity == value;
    
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedSeverity = value;
        });
        _loadFlags();
      },
      selectedColor: Theme.of(context).primaryColor.withOpacity(0.3),
    );
  }
  
  Widget _buildFlagCard(Map<String, dynamic> flag) {
    final flagType = flag['flag_type'] ?? 'Unknown';
    final severity = flag['severity'] ?? 'medium';
    final employeeName = flag['employee_name'] ?? 'Unknown';
    final description = flag['description'] ?? '';
    DateTime createdAt;
    if (flag['created_at'] != null) {
      try {
        createdAt = DateTime.parse(flag['created_at'].toString());
      } catch (e) {
        createdAt = DateTime.now();
      }
    } else {
      createdAt = DateTime.now();
    }
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _getSeverityColor(severity).withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            _getFlagTypeIcon(flagType),
            color: _getSeverityColor(severity),
          ),
        ),
        title: Text(
          employeeName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$flagType - $description'),
            const SizedBox(height: 4),
            Text(
              DateFormat('yyyy-MM-dd HH:mm').format(createdAt),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Severity badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _getSeverityColor(severity),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                severity.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Approve button
            IconButton(
              icon: const Icon(Icons.check_circle_outline, color: Colors.green),
              onPressed: () => _resolveFlag(flag['id'], employeeName),
            ),
          ],
        ),
        onTap: () {
          _showFlagDetails(flag);
        },
      ),
    );
  }
  
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 80,
            color: Colors.green[300],
          ),
          const SizedBox(height: 16),
          Text(
            'لا توجد تنبيهات',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'جميع الموظفين يعملون بشكل طبيعي',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }
  
  void _showFlagDetails(Map<String, dynamic> flag) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              padding: const EdgeInsets.all(16),
              child: ListView(
                controller: scrollController,
                children: [
                  const Center(
                    child: Icon(Icons.drag_handle, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'تفاصيل التنبيه',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const Divider(height: 32),
                  
                  _buildDetailRow('الموظف', flag['employee_name'] ?? 'Unknown'),
                  _buildDetailRow('الوظيفة', flag['employee_role'] ?? 'Unknown'),
                  _buildDetailRow('نوع التنبيه', flag['flag_type'] ?? 'Unknown'),
                  _buildDetailRow('الخطورة', flag['severity'] ?? 'Unknown'),
                  _buildDetailRow('الوصف', flag['description'] ?? 'No description'),
                  
                  const SizedBox(height: 24),
                  
                  // Actions
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.info_outline),
                          label: const Text('عرض التفاصيل الكاملة'),
                          onPressed: () {
                            // Navigate to pulse detail page
                            Navigator.pop(context);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.check),
                          label: const Text('موافقة'),
                          onPressed: () {
                            Navigator.pop(context);
                            _resolveFlag(flag['id'], flag['employee_name'] ?? 'Unknown');
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
  
  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}
