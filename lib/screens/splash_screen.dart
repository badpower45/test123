import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  static const routeName = '/';

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _iconFade;
  late final Animation<double> _iconScale;
  late final Animation<double> _wordFade;
  late final Animation<double> _wordScale;
  late final Animation<Offset> _workersSlide;
  late final Animation<double> _workersFade;
  late final Animation<double> _taglineFade;
  late final Animation<double> _accentWidth;
  late final Animation<double> _glowPulse;
  late final Animation<Color?> _backgroundStart;
  late final Animation<Color?> _backgroundEnd;
  late final Animation<Offset> _taglineSlide;
  late final Animation<double> _ctaFade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..forward();
    _iconFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.35, curve: Curves.easeIn),
    );
    _iconScale = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOutBack),
      ),
    );
    _wordFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.18, 0.62, curve: Curves.easeOut),
    );
    _wordScale = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 0.68, curve: Curves.easeOutBack),
      ),
    );
    _workersSlide = Tween<Offset>(
      begin: const Offset(0, 0.35),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.35, 0.8, curve: Curves.easeOut),
      ),
    );
    _workersFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.35, 0.85, curve: Curves.easeIn),
    );
    _taglineFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.6, 1.0, curve: Curves.easeIn),
    );
    _accentWidth = Tween<double>(begin: 36, end: 148).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.55, 0.92, curve: Curves.easeOutCubic),
      ),
    );
    _glowPulse = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.1, 0.95, curve: Curves.easeInOutSine),
    );
    _backgroundStart = ColorTween(
      begin: const Color(0xFF0F172A),
      end: const Color(0xFF1E2C4A),
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 1.0, curve: Curves.easeInOut),
      ),
    );
    _backgroundEnd = ColorTween(
      begin: const Color(0xFF1E2C4A),
      end: const Color(0xFF274B7A),
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 1.0, curve: Curves.easeInOut),
      ),
    );
    _taglineSlide = Tween<Offset>(
      begin: const Offset(0, 0.25),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.62, 0.94, curve: Curves.easeOutCubic),
      ),
    );
    _ctaFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.78, 1.0, curve: Curves.easeIn),
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _navigateToLogin();
        });
      }
    });
  }

  void _navigateToLogin() {
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 550),
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOut,
            ),
            child: const LoginScreen(),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = GoogleFonts.poppins(
      textStyle: theme.textTheme.displayMedium?.copyWith(
            color: AppColors.onPrimary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ) ??
          const TextStyle(
            fontSize: 42,
            color: AppColors.onPrimary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
    );
    final secondaryStyle = GoogleFonts.poppins(
      textStyle: theme.textTheme.headlineSmall?.copyWith(
            color: AppColors.onPrimary.withOpacity(0.92),
            fontWeight: FontWeight.w600,
            letterSpacing: 3.2,
          ) ??
          const TextStyle(
            fontSize: 26,
            color: AppColors.onPrimary,
            fontWeight: FontWeight.w600,
            letterSpacing: 3.2,
          ),
    );
    final taglineStyle = GoogleFonts.poppins(
      textStyle: theme.textTheme.bodyLarge?.copyWith(
            color: AppColors.onPrimary.withOpacity(0.82),
            fontWeight: FontWeight.w500,
            height: 1.5,
          ) ??
          const TextStyle(
            fontSize: 18,
            color: AppColors.onPrimary,
            fontWeight: FontWeight.w500,
            height: 1.5,
          ),
    );
    final ctaStyle = GoogleFonts.poppins(
      textStyle: theme.textTheme.titleSmall?.copyWith(
            color: AppColors.onPrimary.withOpacity(0.9),
            fontWeight: FontWeight.w600,
          ) ??
          const TextStyle(
            fontSize: 15,
            color: AppColors.onPrimary,
            fontWeight: FontWeight.w600,
          ),
    );

    return Scaffold(
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final gradient = LinearGradient(
            colors: [
              _backgroundStart.value ?? const Color(0xFF0F172A),
              _backgroundEnd.value ?? const Color(0xFF274B7A),
            ],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          );
          return Container(
            decoration: BoxDecoration(gradient: gradient),
            child: child,
          );
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              top: -140,
              right: -60,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  return Transform.rotate(
                    angle: 0.12 * _controller.value,
                    child: Container(
                      width: 280,
                      height: 280,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.05),
                      ),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              bottom: -120,
              left: -40,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  return Transform.scale(
                    scale: 0.8 + (_controller.value * 0.2),
                    child: Container(
                      width: 240,
                      height: 240,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(40),
                        color: Colors.white.withOpacity(0.04),
                      ),
                    ),
                  );
                },
              ),
            ),
            AnimatedBuilder(
              animation: _glowPulse,
              builder: (context, child) {
                final glowSize = 220 + (_glowPulse.value * 90);
                return Container(
                  width: glowSize,
                  height: glowSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color:
                            Colors.white.withOpacity(0.08 + (_glowPulse.value * 0.12)),
                        blurRadius: 70 + (_glowPulse.value * 140),
                        spreadRadius: 12 * _glowPulse.value,
                      ),
                    ],
                  ),
                );
              },
            ),
            SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ScaleTransition(
                    scale: _iconScale,
                    child: FadeTransition(
                      opacity: _iconFade,
                      child: Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.12),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.18),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 20,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Image.asset(
                          'assets/images/app_icon.png',
                          height: 96,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return Icon(
                              Icons.favorite_rounded,
                              color: AppColors.onPrimary.withOpacity(0.9),
                              size: 64,
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  ScaleTransition(
                    scale: _wordScale,
                    child: FadeTransition(
                      opacity: _wordFade,
                      child: Text('Oldies', style: titleStyle),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SlideTransition(
                    position: _workersSlide,
                    child: FadeTransition(
                      opacity: _workersFade,
                      child: Text('Workers', style: secondaryStyle),
                    ),
                  ),
                  const SizedBox(height: 24),
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) => Opacity(
                      opacity: _taglineFade.value,
                      child: Container(
                        width: _accentWidth.value,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.88),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withOpacity(0.4),
                              blurRadius: 12,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SlideTransition(
                    position: _taglineSlide,
                    child: FadeTransition(
                      opacity: _taglineFade,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          'A trusted attendance command center built for timeless teams.',
                          textAlign: TextAlign.center,
                          style: taglineStyle,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  FadeTransition(
                    opacity: _ctaFade,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.18),
                            width: 1,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 10,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withOpacity(0.18),
                                ),
                                child: const Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Transitioning to the control room…',
                                style: ctaStyle,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
