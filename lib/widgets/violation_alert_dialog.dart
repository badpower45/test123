import 'package:flutter/material.dart';
import '../services/pulse_tracking_service.dart';

/// Violation Alert Dialog - Shows when employee is outside geofence
class ViolationAlertDialog extends StatelessWidget {
  final String message;
  final ViolationSeverity severity;
  final VoidCallback onAcknowledge;

  const ViolationAlertDialog({
    super.key,
    required this.message,
    required this.severity,
    required this.onAcknowledge,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _getBackgroundColor(),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: _getBorderColor().withOpacity(0.3),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
          border: Border.all(
            color: _getBorderColor(),
            width: 3,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _getBorderColor().withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _getIcon(),
                size: 60,
                color: _getBorderColor(),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Title
            Text(
              _getTitle(),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: _getBorderColor(),
              ),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 16),
            
            // Message
            Text(
              message,
              style: const TextStyle(
                fontSize: 18,
                height: 1.5,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 24),
            
            // Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  onAcknowledge();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _getBorderColor(),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'حسناً، فهمت',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getBackgroundColor() {
    switch (severity) {
      case ViolationSeverity.warning:
        return Colors.orange.shade50;
      case ViolationSeverity.penalty:
        return Colors.red.shade50;
      case ViolationSeverity.resolved:
        return Colors.green.shade50;
    }
  }

  Color _getBorderColor() {
    switch (severity) {
      case ViolationSeverity.warning:
        return Colors.orange.shade700;
      case ViolationSeverity.penalty:
        return Colors.red.shade700;
      case ViolationSeverity.resolved:
        return Colors.green.shade700;
    }
  }

  IconData _getIcon() {
    switch (severity) {
      case ViolationSeverity.warning:
        return Icons.warning_amber_rounded;
      case ViolationSeverity.penalty:
        return Icons.error_rounded;
      case ViolationSeverity.resolved:
        return Icons.check_circle_rounded;
    }
  }

  String _getTitle() {
    switch (severity) {
      case ViolationSeverity.warning:
        return 'تحذير!';
      case ViolationSeverity.penalty:
        return 'عقوبة!';
      case ViolationSeverity.resolved:
        return 'تم الحل';
    }
  }
}
