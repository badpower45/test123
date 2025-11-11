import 'package:flutter/material.dart';

/// BLV Quick Status Widget
/// Compact widget showing current BLV status - suitable for home page
class BLVQuickStatus extends StatelessWidget {
  const BLVQuickStatus({
    super.key,
    required this.isCheckedIn,
    this.lastScore,
    this.onTap,
  });

  final bool isCheckedIn;
  final int? lastScore;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _getBackgroundColor().withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _getBackgroundColor().withOpacity(0.3),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            // Status Icon
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _getBackgroundColor(),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _getStatusIcon(),
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),

            // Status Text and Score
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isCheckedIn ? 'Checked In' : 'Checked Out',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (lastScore != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          'BLV Score: ',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        Text(
                          '$lastScore%',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _getScoreColor(lastScore!),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // Arrow or Score Badge
            if (lastScore != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getScoreColor(lastScore!),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$lastScore%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
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

  Color _getBackgroundColor() {
    if (!isCheckedIn) {
      return Colors.grey;
    }

    if (lastScore == null) {
      return Colors.blue;
    }

    if (lastScore! >= 80) return Colors.green;
    if (lastScore! >= 60) return Colors.orange;
    return Colors.red;
  }

  IconData _getStatusIcon() {
    if (!isCheckedIn) {
      return Icons.logout;
    }

    if (lastScore == null) {
      return Icons.check_circle;
    }

    if (lastScore! >= 80) return Icons.verified;
    if (lastScore! >= 60) return Icons.check_circle;
    return Icons.warning;
  }

  Color _getScoreColor(int score) {
    if (score >= 80) return Colors.green;
    if (score >= 60) return Colors.orange;
    return Colors.red;
  }
}
