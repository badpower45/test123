import 'package:flutter/material.dart';

/// BLV Status Card Widget
/// Displays current check-in status and last BLV score
class BLVStatusCard extends StatelessWidget {
  const BLVStatusCard({
    super.key,
    required this.status,
    this.lastScore,
    this.lastValidationType,
    this.lastValidationTime,
    this.isLoading = false,
  });

  final String status; // 'Checked-In', 'Checked-Out', 'Out of Range', etc.
  final int? lastScore; // 0-100
  final String? lastValidationType; // 'Check-in', 'Pulse', 'Check-out'
  final DateTime? lastValidationTime;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _getGradientColors(),
          ),
        ),
        child: isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status Section
                  Row(
                    children: [
                      Icon(
                        _getStatusIcon(),
                        color: Colors.white,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Current Status',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              status,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  if (lastScore != null) ...[
                    const SizedBox(height: 20),
                    const Divider(color: Colors.white30, thickness: 1),
                    const SizedBox(height: 20),

                    // Score Section
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Last BLV Score',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    '$lastScore',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 48,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const Text(
                                    '%',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 24,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              if (lastValidationType != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  lastValidationType!,
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                              if (lastValidationTime != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  _formatTime(lastValidationTime!),
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        // Score gauge
                        SizedBox(
                          width: 100,
                          height: 100,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox(
                                width: 100,
                                height: 100,
                                child: CircularProgressIndicator(
                                  value: lastScore! / 100,
                                  strokeWidth: 10,
                                  backgroundColor: Colors.white24,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    _getScoreColor(lastScore!),
                                  ),
                                ),
                              ),
                              Icon(
                                _getScoreIcon(lastScore!),
                                color: Colors.white,
                                size: 40,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  List<Color> _getGradientColors() {
    if (lastScore == null) {
      // Default gradient based on status
      if (status.toLowerCase().contains('checked-in')) {
        return [const Color(0xFF4CAF50), const Color(0xFF2E7D32)];
      } else if (status.toLowerCase().contains('out')) {
        return [const Color(0xFFF44336), const Color(0xFFC62828)];
      }
      return [const Color(0xFF2196F3), const Color(0xFF1565C0)];
    }

    // Gradient based on score
    if (lastScore! >= 80) {
      return [const Color(0xFF4CAF50), const Color(0xFF2E7D32)]; // Green
    } else if (lastScore! >= 60) {
      return [const Color(0xFFFF9800), const Color(0xFFF57C00)]; // Orange
    } else {
      return [const Color(0xFFF44336), const Color(0xFFC62828)]; // Red
    }
  }

  IconData _getStatusIcon() {
    if (status.toLowerCase().contains('checked-in')) {
      return Icons.check_circle;
    } else if (status.toLowerCase().contains('out')) {
      return Icons.cancel;
    } else if (status.toLowerCase().contains('suspicious')) {
      return Icons.warning;
    }
    return Icons.info;
  }

  Color _getScoreColor(int score) {
    if (score >= 80) return Colors.white;
    if (score >= 60) return Colors.white;
    return Colors.white;
  }

  IconData _getScoreIcon(int score) {
    if (score >= 80) return Icons.verified;
    if (score >= 60) return Icons.check;
    return Icons.warning;
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} min ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} hr ago';
    } else {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
  }
}
