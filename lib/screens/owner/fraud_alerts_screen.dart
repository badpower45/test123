import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_fraud_alerts_service.dart';

/// Fraud Alerts Screen for Managers/Owners
/// Shows fraud detection alerts with ability to review and resolve
class FraudAlertsScreen extends StatefulWidget {
  const FraudAlertsScreen({
    super.key,
    required this.branchId,
    required this.userId,
  });

  final String branchId;
  final String userId;

  @override
  State<FraudAlertsScreen> createState() => _FraudAlertsScreenState();
}

class _FraudAlertsScreenState extends State<FraudAlertsScreen> {
  List<FraudAlert> _alerts = [];
  Map<String, dynamic>? _stats;
  bool _isLoading = true;
  bool _showResolved = false;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _loadData();
    _subscribeToAlerts();
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final results = await Future.wait([
      _showResolved
          ? SupabaseFraudAlertsService.getAllAlerts(branchId: widget.branchId)
          : SupabaseFraudAlertsService.getUnresolvedAlerts(
              branchId: widget.branchId),
      SupabaseFraudAlertsService.getFraudStats(branchId: widget.branchId),
    ]);

    setState(() {
      _alerts = results[0] as List<FraudAlert>;
      _stats = results[1] as Map<String, dynamic>;
      _isLoading = false;
    });
  }

  void _subscribeToAlerts() {
    _channel = SupabaseFraudAlertsService.subscribeToFraudAlerts(
      branchId: widget.branchId,
      onAlert: (alert) {
        if (mounted) {
          setState(() {
            _alerts.insert(0, alert);
          });

          // Show snackbar for new alert
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '🚨 New fraud alert: ${alert.employeeName}',
                style: const TextStyle(color: Colors.white),
              ),
              backgroundColor: alert.severity > 0.8 ? Colors.red : Colors.orange,
              action: SnackBarAction(
                label: 'View',
                textColor: Colors.white,
                onPressed: () => _showAlertDetails(alert),
              ),
            ),
          );
        }
      },
    );
  }

  Future<void> _unsubscribe() async {
    if (_channel != null) {
      await SupabaseFraudAlertsService.unsubscribeFromFraudAlerts(_channel!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fraud Alerts'),
        actions: [
          IconButton(
            icon: Icon(_showResolved ? Icons.filter_list_off : Icons.filter_list),
            onPressed: () {
              setState(() {
                _showResolved = !_showResolved;
              });
              _loadData();
            },
            tooltip: _showResolved ? 'Hide Resolved' : 'Show All',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_stats != null) _buildStatsHeader(_stats!),
                Expanded(child: _buildAlertsList()),
              ],
            ),
    );
  }

  Widget _buildStatsHeader(Map<String, dynamic> stats) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[100],
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              'Total',
              stats['total_alerts'].toString(),
              Icons.warning,
              Colors.blue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              'Critical',
              stats['critical_alerts'].toString(),
              Icons.error,
              Colors.red,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              'Pending',
              stats['pending_alerts'].toString(),
              Icons.pending,
              Colors.orange,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertsList() {
    if (_alerts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, size: 64, color: Colors.green[300]),
            const SizedBox(height: 16),
            Text(
              _showResolved ? 'No alerts found' : 'No pending alerts',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _alerts.length,
        itemBuilder: (context, index) {
          final alert = _alerts[index];
          return _buildAlertCard(alert);
        },
      ),
    );
  }

  Widget _buildAlertCard(FraudAlert alert) {
    final severityColor = alert.severity > 0.8
        ? Colors.red
        : alert.severity > 0.5
            ? Colors.orange
            : Colors.yellow[700]!;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: alert.isResolved ? 1 : 3,
      child: InkWell(
        onTap: () => _showAlertDetails(alert),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: severityColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: severityColor),
                    ),
                    child: Text(
                      alert.severityText.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: severityColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (alert.isResolved)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.check_circle, size: 14, color: Colors.green),
                          SizedBox(width: 4),
                          Text(
                            'RESOLVED',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const Spacer(),
                  if (alert.totalScore != null)
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: severityColor.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${alert.totalScore}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: severityColor,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                alert.alertTypeDisplay,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Employee: ${alert.employeeName}',
                style: TextStyle(fontSize: 14, color: Colors.grey[700]),
              ),
              Text(
                _formatTime(alert.createdAt),
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAlertDetails(FraudAlert alert) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Alert Details',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildDetailRow('Employee', alert.employeeName),
                _buildDetailRow('Alert Type', alert.alertTypeDisplay),
                _buildDetailRow('Severity', alert.severityText),
                if (alert.totalScore != null)
                  _buildDetailRow('BLV Score', '${alert.totalScore}/100'),
                _buildDetailRow('Time', _formatFullTime(alert.createdAt)),
                if (alert.isResolved) ...[
                  const Divider(height: 32),
                  _buildDetailRow('Resolved At', _formatFullTime(alert.resolvedAt!)),
                  if (alert.resolutionNotes != null)
                    _buildDetailRow('Notes', alert.resolutionNotes!),
                ],
                if (!alert.isResolved) ...[
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _resolveAlert(alert),
                      icon: const Icon(Icons.check),
                      label: const Text('Mark as Resolved'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _resolveAlert(FraudAlert alert) async {
    final notes = await _showNotesDialog();
    if (notes == null) return;

    Navigator.pop(context); // Close bottom sheet

    final success = await SupabaseFraudAlertsService.resolveAlert(
      alertId: alert.id,
      resolvedBy: widget.userId,
      notes: notes.isEmpty ? null : notes,
    );

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Alert resolved successfully'),
          backgroundColor: Colors.green,
        ),
      );
      _loadData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to resolve alert'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<String?> _showNotesDialog() async {
    final controller = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resolution Notes'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Add notes (optional)',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Resolve'),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${time.day}/${time.month}/${time.year}';
    }
  }

  String _formatFullTime(DateTime time) {
    return '${time.day}/${time.month}/${time.year} at ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
