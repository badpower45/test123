import 'package:flutter/material.dart';
import '../providers/blv_provider.dart';
import 'blv_status_card.dart';
import 'blv_quick_status.dart';

/// BLV Realtime Status Widget
/// Example widget showing how to integrate BLVProvider with UI components
/// This widget automatically updates when new validation events occur
class BLVRealtimeStatusWidget extends StatefulWidget {
  const BLVRealtimeStatusWidget({
    super.key,
    required this.employeeId,
    this.compact = false,
    this.onTap,
  });

  final String employeeId;
  final bool compact; // If true, shows BLVQuickStatus; else shows BLVStatusCard
  final VoidCallback? onTap;

  @override
  State<BLVRealtimeStatusWidget> createState() => _BLVRealtimeStatusWidgetState();
}

class _BLVRealtimeStatusWidgetState extends State<BLVRealtimeStatusWidget> {
  late BLVProvider _blvProvider;

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

  @override
  Widget build(BuildContext context) {
    if (widget.compact) {
      return BLVQuickStatus(
        isCheckedIn: _blvProvider.isCheckedIn,
        lastScore: _blvProvider.lastScore,
        onTap: widget.onTap,
      );
    }

    return BLVStatusCard(
      status: _getStatusText(),
      lastScore: _blvProvider.lastScore,
      lastValidationType: _blvProvider.lastValidationType,
      lastValidationTime: _blvProvider.lastValidationTime,
      isLoading: _blvProvider.isLoading && _blvProvider.latestValidation == null,
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
}
