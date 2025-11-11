import 'package:flutter/material.dart';
import '../models/blv_validation_event.dart';

/// BLV Score Breakdown Widget
/// Shows detailed breakdown of individual BLV component scores
class BLVScoreBreakdown extends StatelessWidget {
  const BLVScoreBreakdown({
    super.key,
    required this.event,
  });

  final BLVValidationEvent event;

  @override
  Widget build(BuildContext context) {
    final scoreItems = _buildScoreItems();

    if (scoreItems.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.analytics_outlined,
                  color: Theme.of(context).primaryColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Score Breakdown',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...scoreItems,
          ],
        ),
      ),
    );
  }

  List<Widget> _buildScoreItems() {
    final List<Widget> items = [];

    // WiFi Score
    if (event.wifiScore != null) {
      items.add(_buildScoreItem(
        icon: Icons.wifi,
        label: 'WiFi Match',
        score: event.wifiScore!,
        maxScore: 30,
        color: Colors.blue,
      ));
    }

    // GPS Score
    if (event.gpsScore != null) {
      items.add(_buildScoreItem(
        icon: Icons.location_on,
        label: 'GPS Location',
        score: event.gpsScore!,
        maxScore: 20,
        color: Colors.green,
      ));
    }

    // Cell Tower Score
    if (event.cellScore != null) {
      items.add(_buildScoreItem(
        icon: Icons.cell_tower,
        label: 'Cell Tower',
        score: event.cellScore!,
        maxScore: 15,
        color: Colors.purple,
      ));
    }

    // Sound Score
    if (event.soundScore != null) {
      items.add(_buildScoreItem(
        icon: Icons.volume_up,
        label: 'Ambient Sound',
        score: event.soundScore!,
        maxScore: 15,
        color: Colors.orange,
      ));
    }

    // Motion Score
    if (event.motionScore != null) {
      items.add(_buildScoreItem(
        icon: Icons.directions_walk,
        label: 'Motion Pattern',
        score: event.motionScore!,
        maxScore: 10,
        color: Colors.teal,
      ));
    }

    // Bluetooth Score
    if (event.bluetoothScore != null) {
      items.add(_buildScoreItem(
        icon: Icons.bluetooth,
        label: 'Bluetooth Beacons',
        score: event.bluetoothScore!,
        maxScore: 5,
        color: Colors.indigo,
      ));
    }

    // Light Score
    if (event.lightScore != null) {
      items.add(_buildScoreItem(
        icon: Icons.light_mode,
        label: 'Light Level',
        score: event.lightScore!,
        maxScore: 3,
        color: Colors.amber,
      ));
    }

    // Battery Score
    if (event.batteryScore != null) {
      items.add(_buildScoreItem(
        icon: Icons.battery_charging_full,
        label: 'Battery Pattern',
        score: event.batteryScore!,
        maxScore: 2,
        color: Colors.red,
      ));
    }

    return items;
  }

  Widget _buildScoreItem({
    required IconData icon,
    required String label,
    required int score,
    required int maxScore,
    required Color color,
  }) {
    final percentage = (score / maxScore * 100).clamp(0, 100).round();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                '$score/$maxScore',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: _getScoreColor(percentage),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: score / maxScore,
              minHeight: 6,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(
                _getScoreColor(percentage),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getScoreColor(int percentage) {
    if (percentage >= 80) return Colors.green;
    if (percentage >= 60) return Colors.orange;
    return Colors.red;
  }
}
