import 'package:flutter/material.dart';
import '../models/blv_validation_event.dart';

/// BLV Validation History Item Widget
/// Displays a single validation event in the history list
class BLVValidationHistoryItem extends StatelessWidget {
  const BLVValidationHistoryItem({
    super.key,
    required this.event,
    this.onTap,
    this.showDate = true,
  });

  final BLVValidationEvent event;
  final VoidCallback? onTap;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _getBorderColor().withOpacity(0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Status Icon
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _getStatusColor().withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _getStatusIcon(),
                color: _getStatusColor(),
                size: 24,
              ),
            ),
            const SizedBox(width: 16),

            // Event Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Validation Type
                      Text(
                        event.displayType,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Status Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _getStatusColor().withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _getStatusColor(),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          _getStatusText(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _getStatusColor(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Time and Score
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 14,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatTime(event.timestamp),
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                      if (event.scorePercentage != null) ...[
                        const SizedBox(width: 12),
                        Icon(
                          Icons.score,
                          size: 14,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Score: ${event.scorePercentage}%',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _getScoreColor(event.scorePercentage!),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // Score Badge or Arrow
            if (event.scorePercentage != null)
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: _getScoreColor(event.scorePercentage!).withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _getScoreColor(event.scorePercentage!),
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Text(
                    '${event.scorePercentage}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _getScoreColor(event.scorePercentage!),
                    ),
                  ),
                ),
              )
            else
              Icon(
                Icons.chevron_right,
                color: Colors.grey[400],
              ),
          ],
        ),
      ),
    );
  }

  Color _getBorderColor() {
    if (event.isApproved == false || event.status == 'REJECTED') {
      return Colors.red;
    } else if (event.status == 'OUT' || event.status == 'SUSPECT') {
      return Colors.orange;
    }
    return Colors.green;
  }

  Color _getStatusColor() {
    if (event.isApproved == false || event.status == 'REJECTED') {
      return Colors.red;
    } else if (event.status == 'OUT' || event.status == 'SUSPECT') {
      return Colors.orange;
    }
    return Colors.green;
  }

  IconData _getStatusIcon() {
    if (event.isApproved == false || event.status == 'REJECTED') {
      return Icons.cancel;
    } else if (event.status == 'OUT') {
      return Icons.location_off;
    } else if (event.status == 'SUSPECT') {
      return Icons.warning;
    } else if (event.validationType.toLowerCase().contains('check-in')) {
      return Icons.login;
    } else if (event.validationType.toLowerCase().contains('check-out')) {
      return Icons.logout;
    }
    return Icons.radio_button_checked;
  }

  String _getStatusText() {
    if (event.isApproved == false || event.status == 'REJECTED') {
      return 'Rejected';
    } else if (event.status == 'OUT') {
      return 'Out of Range';
    } else if (event.status == 'SUSPECT') {
      return 'Suspicious';
    }
    return 'Verified';
  }

  Color _getScoreColor(int score) {
    if (score >= 80) return Colors.green;
    if (score >= 60) return Colors.orange;
    return Colors.red;
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final eventDate = DateTime(time.year, time.month, time.day);

    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    final timeStr = '$hour:$minute';

    if (eventDate == today) {
      return timeStr;
    } else if (eventDate == yesterday) {
      return 'Yesterday $timeStr';
    } else if (now.difference(time).inDays < 7) {
      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return '${weekdays[time.weekday - 1]} $timeStr';
    } else {
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${months[time.month - 1]} ${time.day}, $timeStr';
    }
  }
}
