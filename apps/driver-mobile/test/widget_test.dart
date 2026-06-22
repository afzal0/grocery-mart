import 'package:flutter_test/flutter_test.dart';
import 'package:driver_app/main.dart';

void main() {
  testWidgets('driver landing renders title and CTA', (tester) async {
    await tester.pumpWidget(const GroceryMartDriverApp());
    expect(find.textContaining('Grocery-Mart'), findsWidgets);
    expect(find.text('Go online'), findsOneWidget);
  });
}
