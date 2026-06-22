import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/main.dart';

void main() {
  testWidgets('customer landing renders title and CTA', (tester) async {
    await tester.pumpWidget(const GroceryMartCustomerApp());
    expect(find.textContaining('Grocery-Mart'), findsWidgets);
    expect(find.text('Get started'), findsOneWidget);
  });
}
