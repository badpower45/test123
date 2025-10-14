import 'package:flutter/material.dart';

class AppColors {
  const AppColors._();

  // Primary Colors - Modern Professional Palette
  static const Color primaryOrange = Color(0xFFF37021);
  static const Color primaryDark = Color(0xFFD85A0F);
  static const Color primaryLight = Color(0xFFFFA365);
  
  // Neutral Colors - Clean Background System
  static const Color background = Color(0xFFFAFAFA);
  static const Color surface = Colors.white;
  static const Color surfaceVariant = Color(0xFFF5F5F5);
  
  // Text Colors - Arabic-Optimized Contrast
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF666666);
  static const Color textTertiary = Color(0xFF999999);
  
  // Semantic Colors
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);
  
  // Status Colors
  static const Color statusActive = Color(0xFF10B981);
  static const Color statusInactive = Color(0xFF6B7280);
  static const Color statusPending = Color(0xFFF59E0B);
  
  // Legacy (for backward compatibility)
  static const Color onPrimary = Colors.white;
  static const Color danger = Color(0xFFEF4444);
  
  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryOrange, primaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient subtleGradient = LinearGradient(
    colors: [Color(0xFFFFF5F0), Colors.white],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}
