import 'package:flutter_test/flutter_test.dart';
import 'package:hesam_void/main.dart';

void main() {
  testWidgets('App launches correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const HesamVoidApp());

    // Verify splash screen loads
    expect(find.text('HESAM VOID'), findsOneWidget);
  });
}
