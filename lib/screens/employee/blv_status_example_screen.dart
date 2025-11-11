import 'package:flutter/material.dart';
import '../../providers/blv_provider.dart';
import '../../widgets/blv_status_card.dart';
import '../../widgets/blv_validation_history_list.dart';

/// BLV Status Example Screen
/// Example implementation showing how to use BLVProvider with real-time updates
/// This can be used as a reference for integrating BLV into the employee home page
class BLVStatusExampleScreen extends StatefulWidget {
  const BLVStatusExampleScreen({
    super.key,
    required this.employeeId,
  });

  final String employeeId;

  @override
  State<BLVStatusExampleScreen> createState() => _BLVStatusExampleScreenState();
}

class _BLVStatusExampleScreenState extends State<BLVStatusExampleScreen> {
  late BLVProvider _blvProvider;
  String _selectedPeriod = 'all'; // 'all', 'today', 'week', 'month'

  @override
  void initState() {
    super.initState();
    _blvProvider = BLVProvider(employeeId: widget.employeeId);
    _blvProvider.addListener(_onProviderUpdate);
  }

  @override
  void dispose() {
    _blvProvider.removeListener(_onProviderUpdate);
    _blvProvider.dispose();
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
      appBar: AppBar(
        title: const Text('BLV Status'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _handleRefresh,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Status Card
          Padding(
            padding: const EdgeInsets.all(16),
            child: BLVStatusCard(
              status: _getStatusText(),
              lastScore: _blvProvider.lastScore,
              lastValidationType: _blvProvider.lastValidationType,
              lastValidationTime: _blvProvider.lastValidationTime,
              isLoading: _blvProvider.isLoading &&
                        _blvProvider.latestValidation == null,
            ),
          ),

          // Stats Summary (if available)
          if (_blvProvider.validationStats != null)
            _buildStatsRow(_blvProvider.validationStats!),

          // Period Filter
          _buildPeriodFilter(),

          const SizedBox(height: 8),

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
      ),
    );
  }

  Widget _buildStatsRow(Map<String, dynamic> stats) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            'Total',
            stats['total'].toString(),
            Icons.list,
            Colors.blue,
          ),
          _buildStatItem(
            'Approved',
            stats['approved'].toString(),
            Icons.check_circle,
            Colors.green,
          ),
          _buildStatItem(
            'Avg Score',
            '${stats['average_score']}%',
            Icons.analytics,
            Colors.orange,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildPeriodFilter() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _buildFilterChip('All', 'all'),
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
}
