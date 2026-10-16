import 'package:flutter_test/flutter_test.dart';
import 'package:yunan_yanik/main.dart';

void main() {
  testWidgets('Yunan Yanık VIP Login screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const YunanYanikVipApp());
    expect(find.text('YUNAN YANIK VIP'), findsOneWidget);
  });
}
