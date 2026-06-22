import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:driver_app/main.dart';

void main() {
  testWidgets('driver app boots to the login gate', (tester) async {
    await tester.pumpWidget(const GroceryMartDriverApp());
    await tester.pump();

    // The auth gate shows the branded login card with a sign-in CTA.
    expect(find.textContaining('Grocery-Mart'), findsWidgets);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2)); // email + password
  });
}
