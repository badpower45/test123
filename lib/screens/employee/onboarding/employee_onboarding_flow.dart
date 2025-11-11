import 'package:flutter/material.dart';
import '../../../services/supabase_auth_service.dart';
import 'employee_onboarding_step1.dart';
import 'employee_onboarding_step2.dart';
import 'employee_onboarding_step3.dart';
import '../employee_main_screen.dart';

class EmployeeOnboardingFlow extends StatefulWidget {
  const EmployeeOnboardingFlow({
    super.key,
    required this.employeeId,
    required this.email,
  });

  final String employeeId;
  final String email;

  @override
  State<EmployeeOnboardingFlow> createState() => _EmployeeOnboardingFlowState();
}

class _EmployeeOnboardingFlowState extends State<EmployeeOnboardingFlow> {
  int _currentStep = 0;
  String? _fullName;
  String? _phone;
  String? _address;
  DateTime? _birthDate;
  bool _isSubmitting = false;

  void _onStep1Next(String fullName, String phone) {
    setState(() {
      _fullName = fullName;
      _phone = phone;
      _currentStep = 1;
    });
  }

  void _onStep2Back() {
    setState(() => _currentStep = 0);
  }

  void _onStep2Next(String address, DateTime birthDate) {
    setState(() {
      _address = address;
      _birthDate = birthDate;
      _currentStep = 2;
    });
  }

  Future<void> _onComplete() async {
    if (_isSubmitting) return;

    setState(() => _isSubmitting = true);

    try {
      // Update employee info in Supabase
      await SupabaseAuthService.updateEmployeeProfile(
        employeeId: widget.employeeId,
        fullName: _fullName!,
        phone: _phone!,
        address: _address!,
        birthDate: _birthDate!,
        email: widget.email,
      );

      // Mark onboarding as complete
      await SupabaseAuthService.markOnboardingComplete(widget.employeeId);

      if (!mounted) return;

      // Navigate to main employee screen
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => EmployeeMainScreen(
            employeeId: widget.employeeId,
            role: 'staff',
            branch: '',
          ),
        ),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      
      setState(() => _isSubmitting = false);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isSubmitting) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('جاري حفظ بياناتك...'),
            ],
          ),
        ),
      );
    }

    switch (_currentStep) {
      case 0:
        return EmployeeOnboardingStep1(
          employeeId: widget.employeeId,
          onNext: _onStep1Next,
        );
      case 1:
        return EmployeeOnboardingStep2(
          employeeId: widget.employeeId,
          onNext: _onStep2Next,
          onBack: _onStep2Back,
        );
      case 2:
        return EmployeeOnboardingStep3(
          employeeName: _fullName ?? '',
          onComplete: _onComplete,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
