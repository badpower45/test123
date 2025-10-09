// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:oldies_workers_app/main.dart';
import 'package:oldies_workers_app/screens/login_screen.dart';
import 'package:oldies_workers_app/screens/splash_screen.dart';

void main() {
  testWidgets('Splash screen transitions to login screen', (tester) async {
    await tester.pumpWidget(const OldiesApp());

    expect(find.byType(SplashScreen), findsOneWidget);

    // Finish the splash animation and navigation delay.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    final exception = tester.takeException();
    expect(exception, isNull, reason: 'Splash navigation threw $exception');

    expect(find.byType(SplashScreen), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
