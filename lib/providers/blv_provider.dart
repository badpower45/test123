import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/blv_validation_event.dart';
import '../services/supabase_blv_service.dart';

/// BLV Provider
/// Manages BLV validation state with real-time updates
class BLVProvider extends ChangeNotifier {
  BLVProvider({required this.employeeId}) {
    _initialize();
  }

  final String employeeId;

  // State
  BLVValidationEvent? _latestValidation;
  List<BLVValidationEvent> _validationHistory = [];
  Map<String, dynamic>? _validationStats;
  bool _isLoading = false;
  String? _error;
  RealtimeChannel? _realtimeChannel;

  // Getters
  BLVValidationEvent? get latestValidation => _latestValidation;
  List<BLVValidationEvent> get validationHistory => _validationHistory;
  Map<String, dynamic>? get validationStats => _validationStats;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Derived state
  String get currentStatus {
    if (_latestValidation == null) return 'Unknown';
    return _latestValidation!.status;
  }

  int? get lastScore {
    return _latestValidation?.scorePercentage;
  }

  String? get lastValidationType {
    return _latestValidation?.displayType;
  }

  DateTime? get lastValidationTime {
    return _latestValidation?.timestamp;
  }

  bool get isCheckedIn {
    if (_latestValidation == null) return false;
    return _latestValidation!.status == 'IN' ||
        _latestValidation!.validationType.toLowerCase().contains('check-in');
  }

  /// Initialize provider
  Future<void> _initialize() async {
    await loadLatestValidation();
    await loadValidationHistory();
    await loadValidationStats();
    _subscribeToRealtime();
  }

  /// Load latest validation
  Future<void> loadLatestValidation() async {
    try {
      _error = null;
      final validation = await SupabaseBLVService.getLatestValidation(
        employeeId: employeeId,
      );

      _latestValidation = validation;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load latest validation: $e';
      debugPrint(_error);
      notifyListeners();
    }
  }

  /// Load validation history
  Future<void> loadValidationHistory({
    int limit = 100,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final history = await SupabaseBLVService.getValidationHistory(
        employeeId: employeeId,
        limit: limit,
        startDate: startDate,
        endDate: endDate,
      );

      _validationHistory = history;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load validation history: $e';
      _isLoading = false;
      debugPrint(_error);
      notifyListeners();
    }
  }

  /// Load validation statistics
  Future<void> loadValidationStats({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final stats = await SupabaseBLVService.getValidationStats(
        employeeId: employeeId,
        startDate: startDate,
        endDate: endDate,
      );

      _validationStats = stats;
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load validation stats: $e');
    }
  }

  /// Load today's validations
  Future<void> loadTodayValidations() async {
    try {
      _isLoading = true;
      notifyListeners();

      final validations = await SupabaseBLVService.getTodayValidations(
        employeeId: employeeId,
      );

      _validationHistory = validations;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load today\'s validations: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load week validations
  Future<void> loadWeekValidations() async {
    try {
      _isLoading = true;
      notifyListeners();

      final validations = await SupabaseBLVService.getWeekValidations(
        employeeId: employeeId,
      );

      _validationHistory = validations;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load week validations: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load month validations
  Future<void> loadMonthValidations() async {
    try {
      _isLoading = true;
      notifyListeners();

      final validations = await SupabaseBLVService.getMonthValidations(
        employeeId: employeeId,
      );

      _validationHistory = validations;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load month validations: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Refresh all data
  Future<void> refresh() async {
    await Future.wait([
      loadLatestValidation(),
      loadValidationHistory(),
      loadValidationStats(),
    ]);
  }

  /// Subscribe to real-time updates
  void _subscribeToRealtime() {
    try {
      _realtimeChannel = SupabaseBLVService.subscribeToValidations(
        employeeId: employeeId,
        onValidation: _handleRealtimeValidation,
      );

      debugPrint('[BLV Provider] Subscribed to real-time updates for employee: $employeeId');
    } catch (e) {
      debugPrint('[BLV Provider] Failed to subscribe to real-time: $e');
    }
  }

  /// Handle real-time validation event
  void _handleRealtimeValidation(BLVValidationEvent event) {
    debugPrint('[BLV Provider] Received real-time validation: ${event.validationType} - ${event.status}');

    // Update latest validation
    if (_latestValidation == null ||
        event.timestamp.isAfter(_latestValidation!.timestamp)) {
      _latestValidation = event;
    }

    // Add to history (at the beginning since it's newest)
    _validationHistory.insert(0, event);

    // Update stats
    loadValidationStats();

    notifyListeners();
  }

  /// Unsubscribe from real-time updates
  Future<void> _unsubscribeFromRealtime() async {
    if (_realtimeChannel != null) {
      await SupabaseBLVService.unsubscribeFromValidations(_realtimeChannel!);
      _realtimeChannel = null;
      debugPrint('[BLV Provider] Unsubscribed from real-time updates');
    }
  }

  @override
  void dispose() {
    _unsubscribeFromRealtime();
    super.dispose();
  }
}
