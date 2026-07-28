import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/employee.dart';
import '../services/geofence_service.dart';
import '../theme/app_colors.dart';

/// 📍 Location Verification Dialog Overlay
/// Shows an active waiting indicator while obtaining precise location,
/// and updates to a success screen with "Verified successfully, start work" when checked-in inside the geofence.
class LocationVerificationDialog extends StatefulWidget {
  final Employee employee;
  const LocationVerificationDialog({super.key, required this.employee});

  @override
  State<LocationVerificationDialog> createState() => _LocationVerificationDialogState();
}

class _LocationVerificationDialogState extends State<LocationVerificationDialog> {
  bool _isValidating = true;
  bool _isSuccess = false;
  String _statusMessage = 'جاري جلب موقعك الدقيق والتحقق من تواجدك في الفرع...';

  @override
  void initState() {
    super.initState();
    _startValidation();
  }

  Future<void> _startValidation() async {
    try {
      final validation = await GeofenceService.validateForCheckIn(widget.employee);
      if (!mounted) return;

      if (validation.isValid) {
        setState(() {
          _isValidating = false;
          _isSuccess = true;
          _statusMessage = 'تم التحقق بنجاح! ابدأ العمل';
        });
        // Delay 1.5 seconds so user can see the success state
        await Future.delayed(const Duration(milliseconds: 1500));
        if (mounted) {
          Navigator.pop(context, validation);
        }
      } else {
        // Pop immediately on failure and let the parent show the standard SnackBar/Alert
        Navigator.pop(context, validation);
      }
    } catch (e) {
      if (mounted) {
        // Pop immediately on exception
        Navigator.pop(context, null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Prevent dismissing by tapping outside or back button
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32.0, horizontal: 24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isValidating) ...[
                const SizedBox(
                  height: 60,
                  width: 60,
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryOrange),
                    strokeWidth: 4.5,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'جاري التحقق من الموقع',
                  style: GoogleFonts.tajawal(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ] else if (_isSuccess) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Color(0xFFE8F5E9), // Light green background
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.success,
                    size: 56,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'تم التحقق بنجاح',
                  style: GoogleFonts.tajawal(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.success,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: GoogleFonts.tajawal(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
