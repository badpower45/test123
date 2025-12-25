import 'package:flutter/material.dart';
import '../../services/app_logger.dart';
import '../../theme/app_colors.dart';

/// Logs viewer page for debugging and troubleshooting
class LogsViewerPage extends StatefulWidget {
  const LogsViewerPage({super.key});

  @override
  State<LogsViewerPage> createState() => _LogsViewerPageState();
}

class _LogsViewerPageState extends State<LogsViewerPage> {
  String _selectedLevel = 'الكل';
  List<Map<String, dynamic>> _logs = [];
  
  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  void _loadLogs() {
    setState(() {
      _logs = AppLogger.instance.getLogsAsMap();
    });
  }

  List<Map<String, dynamic>> get _filteredLogs {
    if (_selectedLevel == 'الكل') {
      return _logs;
    }
    
    String levelFilter;
    switch (_selectedLevel) {
      case 'أخطاء':
        levelFilter = 'ERROR';
        break;
      case 'تحذيرات':
        levelFilter = 'WARNING';
        break;
      case 'معلومات':
        levelFilter = 'INFO';
        break;
      default:
        return _logs;
    }
    
    return _logs.where((log) => log['level'] == levelFilter).toList();
  }

  Color _getLevelColor(String level) {
    switch (level) {
      case 'ERROR':
        return Colors.red;
      case 'WARNING':
        return Colors.orange;
      case 'INFO':
        return Colors.blue;
      case 'DEBUG':
        return Colors.grey;
      default:
        return Colors.black;
    }
  }

  String _getLevelIcon(String level) {
    switch (level) {
      case 'ERROR':
        return '❌';
      case 'WARNING':
        return '⚠️';
      case 'INFO':
        return '🔵';
      case 'DEBUG':
        return '🐛';
      default:
        return '📝';
    }
  }

  String _getLevelArabic(String level) {
    switch (level) {
      case 'ERROR':
        return 'خطأ';
      case 'WARNING':
        return 'تحذير';
      case 'INFO':
        return 'معلومة';
      case 'DEBUG':
        return 'تطوير';
      default:
        return level;
    }
  }

  Future<void> _clearLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('مسح السجلات', textAlign: TextAlign.right),
        content: const Text(
          'هل أنت متأكد من مسح جميع السجلات؟',
          textAlign: TextAlign.right,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('مسح'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      AppLogger.instance.clearLogs();
      _loadLogs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم مسح السجلات'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredLogs = _filteredLogs;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('سجلات التطبيق'),
        backgroundColor: AppColors.primaryOrange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLogs,
            tooltip: 'تحديث',
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: _clearLogs,
            tooltip: 'مسح الكل',
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter chips
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              border: Border(
                bottom: BorderSide(color: Colors.grey[300]!),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const Text(
                    'تصفية: ',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  ...[
                    'الكل',
                    'أخطاء',
                    'تحذيرات',
                    'معلومات',
                  ].map((level) => Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: ChoiceChip(
                      label: Text(level),
                      selected: _selectedLevel == level,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _selectedLevel = level);
                        }
                      },
                      selectedColor: AppColors.primaryOrange,
                      labelStyle: TextStyle(
                        color: _selectedLevel == level ? Colors.white : Colors.black,
                      ),
                    ),
                  )),
                ],
              ),
            ),
          ),
          
          // Stats bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.grey[200],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'إجمالي: ${_logs.length}',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  'معروض: ${filteredLogs.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          
          // Logs list
          Expanded(
            child: filteredLogs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'لا توجد سجلات',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: filteredLogs.length,
                    itemBuilder: (context, index) {
                      final log = filteredLogs[filteredLogs.length - 1 - index]; // Reverse order
                      final level = log['level'] as String;
                      final message = log['message'] as String;
                      final timestamp = log['timestamp'] as DateTime;
                      final tag = log['tag'] as String?;
                      final error = log['error'];
                      
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: ExpansionTile(
                          leading: Text(
                            _getLevelIcon(level),
                            style: const TextStyle(fontSize: 24),
                          ),
                          title: Text(
                            message,
                            style: const TextStyle(fontSize: 14),
                          ),
                          subtitle: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _getLevelColor(level).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _getLevelColor(level),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  _getLevelArabic(level),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _getLevelColor(level),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (tag != null) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    tag,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ),
                              ],
                              const Spacer(),
                              Text(
                                _formatTimestamp(timestamp),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                          children: [
                            if (error != null)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                color: Colors.red[50],
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'تفاصيل الخطأ:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.red,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      error.toString(),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.red[900],
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    
    if (difference.inSeconds < 60) {
      return 'منذ ${difference.inSeconds} ث';
    } else if (difference.inMinutes < 60) {
      return 'منذ ${difference.inMinutes} د';
    } else if (difference.inHours < 24) {
      return 'منذ ${difference.inHours} س';
    } else {
      return '${timestamp.day}/${timestamp.month} ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
  }
}
