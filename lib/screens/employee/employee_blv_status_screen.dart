import 'package:flutter/material.dart';
import '../../providers/blv_provider.dart';
import '../../widgets/blv_status_card.dart';
import '../../widgets/blv_validation_history_list.dart';
import '../../widgets/blv_score_breakdown.dart';

/// Employee BLV Status Screen
/// Complete BLV status screen for employees showing current status,
/// validation history, and statistics with real-time updates
class EmployeeBLVStatusScreen extends StatefulWidget {
  const EmployeeBLVStatusScreen({
    super.key,
    required this.employeeId,
  });

  final String employeeId;

  @override
  State<EmployeeBLVStatusScreen> createState() =>
      _EmployeeBLVStatusScreenState();
}

class _EmployeeBLVStatusScreenState extends State<EmployeeBLVStatusScreen>
    with SingleTickerProviderStateMixin {
  late BLVProvider _blvProvider;
  late TabController _tabController;
  String _selectedPeriod = 'all';

  @override
  void initState() {
    super.initState();
    _blvProvider = BLVProvider(employeeId: widget.employeeId);
    _blvProvider.addListener(_onProviderUpdate);
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _blvProvider.removeListener(_onProviderUpdate);
    _blvProvider.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _onProviderUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _handleRefresh() async {
    await _blvProvider.refresh();
  }

  Future<void> _loadPeriodData(String period) async {
    setState(() {
      _selectedPeriod = period;
    });

    switch (period) {
      case 'today':
        await _blvProvider.loadTodayValidations();
        break;
      case 'week':
        await _blvProvider.loadWeekValidations();
        break;
      case 'month':
        await _blvProvider.loadMonthValidations();
        break;
      default:
        await _blvProvider.loadValidationHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('BLV Status'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _handleRefresh,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showInfoDialog,
            tooltip: 'What is BLV?',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Overview', icon: Icon(Icons.dashboard, size: 20)),
            Tab(text: 'History', icon: Icon(Icons.history, size: 20)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(),
          _buildHistoryTab(),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    return RefreshIndicator(
      onRefresh: _handleRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Main Status Card
            BLVStatusCard(
              status: _getStatusText(),
              lastScore: _blvProvider.lastScore,
              lastValidationType: _blvProvider.lastValidationType,
              lastValidationTime: _blvProvider.lastValidationTime,
              isLoading: _blvProvider.isLoading &&
                  _blvProvider.latestValidation == null,
            ),

            const SizedBox(height: 24),

            // Statistics Section
            if (_blvProvider.validationStats != null) ...[
              Text(
                'Statistics',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              _buildStatsCards(_blvProvider.validationStats!),
              const SizedBox(height: 24),
            ],

            // Latest Validation Details
            if (_blvProvider.latestValidation != null &&
                (_blvProvider.latestValidation!.wifiScore != null ||
                    _blvProvider.latestValidation!.gpsScore != null)) ...[
              Text(
                'Latest Validation Breakdown',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              BLVScoreBreakdown(event: _blvProvider.latestValidation!),
              const SizedBox(height: 24),
            ],

            // Recent Activity Preview
            if (_blvProvider.validationHistory.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Recent Activity',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  TextButton(
                    onPressed: () {
                      _tabController.animateTo(1);
                    },
                    child: const Text('View All'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildRecentActivityPreview(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryTab() {
    return Column(
      children: [
        // Period Filter
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: _buildPeriodFilter(),
        ),

        // History List
        Expanded(
          child: BLVValidationHistoryList(
            events: _blvProvider.validationHistory,
            isLoading: _blvProvider.isLoading,
            onRefresh: _handleRefresh,
            groupByDate: true,
            emptyMessage: _getEmptyMessage(),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsCards(Map<String, dynamic> stats) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Total',
            stats['total'].toString(),
            Icons.list_alt,
            Colors.blue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'Verified',
            stats['approved'].toString(),
            Icons.verified,
            Colors.green,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'Avg Score',
            '${stats['average_score']}%',
            Icons.analytics,
            Colors.orange,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentActivityPreview() {
    final recentEvents = _blvProvider.validationHistory.take(3).toList();

    return Card(
      elevation: 2,
      child: Column(
        children: recentEvents.map((event) {
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: _getEventColor(event.status).withOpacity(0.1),
              child: Icon(
                _getEventIcon(event.validationType),
                color: _getEventColor(event.status),
                size: 20,
              ),
            ),
            title: Text(event.displayType),
            subtitle: Text(_formatTime(event.timestamp)),
            trailing: event.scorePercentage != null
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _getScoreColor(event.scorePercentage!)
                          .withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${event.scorePercentage}%',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _getScoreColor(event.scorePercentage!),
                      ),
                    ),
                  )
                : null,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPeriodFilter() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _buildFilterChip('All Time', 'all'),
          const SizedBox(width: 8),
          _buildFilterChip('Today', 'today'),
          const SizedBox(width: 8),
          _buildFilterChip('This Week', 'week'),
          const SizedBox(width: 8),
          _buildFilterChip('This Month', 'month'),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedPeriod == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          _loadPeriodData(value);
        }
      },
      selectedColor: Theme.of(context).primaryColor.withOpacity(0.2),
      checkmarkColor: Theme.of(context).primaryColor,
    );
  }

  String _getStatusText() {
    if (_blvProvider.latestValidation == null) {
      return 'No Data';
    }

    final status = _blvProvider.currentStatus;
    switch (status.toUpperCase()) {
      case 'IN':
        return 'Checked In';
      case 'OUT':
        return 'Out of Range';
      case 'SUSPECT':
        return 'Suspicious Activity';
      case 'REVIEW_REQUIRED':
        return 'Review Required';
      case 'REJECTED':
        return 'Checked Out';
      default:
        return status;
    }
  }

  String _getEmptyMessage() {
    switch (_selectedPeriod) {
      case 'today':
        return 'No validations today';
      case 'week':
        return 'No validations this week';
      case 'month':
        return 'No validations this month';
      default:
        return 'No validation history yet';
    }
  }

  Color _getEventColor(String status) {
    if (status == 'REJECTED' || status == 'OUT') return Colors.red;
    if (status == 'SUSPECT') return Colors.orange;
    return Colors.green;
  }

  IconData _getEventIcon(String type) {
    if (type.toLowerCase().contains('check-in')) return Icons.login;
    if (type.toLowerCase().contains('check-out')) return Icons.logout;
    return Icons.radio_button_checked;
  }

  Color _getScoreColor(int score) {
    if (score >= 80) return Colors.green;
    if (score >= 60) return Colors.orange;
    return Colors.red;
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
    } else {
      return '${difference.inDays}d ago';
    }
  }

  void _showInfoDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('What is BLV?'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Behavioral Location Verification (BLV) is an advanced system that verifies your presence at work using multiple signals:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              SizedBox(height: 16),
              Text('• WiFi networks detected'),
              Text('• GPS location'),
              Text('• Cell tower signals'),
              Text('• Ambient sound patterns'),
              Text('• Motion sensors'),
              Text('• Battery charging patterns'),
              SizedBox(height: 16),
              Text(
                'Your BLV score shows how confident the system is that you\'re actually at your workplace. A higher score means better verification.',
              ),
              SizedBox(height: 16),
              Text(
                'Score Ranges:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('• 80-100%: Excellent verification'),
              Text('• 60-79%: Good verification'),
              Text('• Below 60%: Needs review'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}
