import 'package:flutter/material.dart';
import '../models/blv_validation_event.dart';
import 'blv_validation_history_item.dart';
import 'blv_score_breakdown.dart';

/// BLV Validation History List Widget
/// Displays a scrollable, grouped list of validation events
class BLVValidationHistoryList extends StatelessWidget {
  const BLVValidationHistoryList({
    super.key,
    required this.events,
    this.isLoading = false,
    this.onRefresh,
    this.onLoadMore,
    this.groupByDate = true,
    this.emptyMessage = 'No validation history yet',
  });

  final List<BLVValidationEvent> events;
  final bool isLoading;
  final Future<void> Function()? onRefresh;
  final VoidCallback? onLoadMore;
  final bool groupByDate;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (isLoading && events.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (events.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              emptyMessage,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    Widget listView = groupByDate
        ? _buildGroupedList(context)
        : _buildSimpleList(context);

    if (onRefresh != null) {
      return RefreshIndicator(
        onRefresh: onRefresh!,
        child: listView,
      );
    }

    return listView;
  }

  Widget _buildSimpleList(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: events.length + (isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == events.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          );
        }

        final event = events[index];
        return BLVValidationHistoryItem(
          event: event,
          onTap: () => _showEventDetails(context, event),
        );
      },
    );
  }

  Widget _buildGroupedList(BuildContext context) {
    final groupedEvents = _groupEventsByDate(events);

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: groupedEvents.length + (isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == groupedEvents.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          );
        }

        final group = groupedEvents[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date Header
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 12, top: 8),
              child: Text(
                group['date'] as String,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                ),
              ),
            ),

            // Events for this date
            ...((group['events'] as List<BLVValidationEvent>).map(
              (event) => BLVValidationHistoryItem(
                event: event,
                onTap: () => _showEventDetails(context, event),
                showDate: false,
              ),
            )),

            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  List<Map<String, dynamic>> _groupEventsByDate(List<BLVValidationEvent> events) {
    final Map<String, List<BLVValidationEvent>> groups = {};

    for (final event in events) {
      final dateKey = _getDateKey(event.timestamp);
      groups.putIfAbsent(dateKey, () => []).add(event);
    }

    return groups.entries.map((entry) {
      return {
        'date': _formatDateHeader(entry.key),
        'events': entry.value,
      };
    }).toList();
  }

  String _getDateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _formatDateHeader(String dateKey) {
    final parts = dateKey.split('-');
    final date = DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    if (date == today) {
      return 'Today';
    } else if (date == yesterday) {
      return 'Yesterday';
    } else if (now.difference(date).inDays < 7) {
      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return weekdays[date.weekday - 1];
    } else {
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${months[date.month - 1]} ${date.day}';
    }
  }

  void _showEventDetails(BuildContext context, BLVValidationEvent event) {
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
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Icon(
                        Icons.analytics,
                        color: Theme.of(context).primaryColor,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Validation Details',
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

                  // Event Info
                  _buildDetailRow(
                    'Type',
                    event.displayType,
                    Icons.category,
                  ),
                  _buildDetailRow(
                    'Time',
                    _formatFullTime(event.timestamp),
                    Icons.access_time,
                  ),
                  _buildDetailRow(
                    'Status',
                    event.displayStatus,
                    Icons.info,
                  ),
                  if (event.scorePercentage != null)
                    _buildDetailRow(
                      'Score',
                      '${event.scorePercentage}%',
                      Icons.score,
                    ),

                  // Score Breakdown
                  if (event.wifiScore != null ||
                      event.gpsScore != null ||
                      event.cellScore != null) ...[
                    const SizedBox(height: 24),
                    BLVScoreBreakdown(event: event),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Text(
            '$label:',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(width: 8),
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

  String _formatFullTime(DateTime time) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];

    final month = months[time.month - 1];
    final day = time.day;
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');

    return '$month $day at $hour:$minute';
  }
}
