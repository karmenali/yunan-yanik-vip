import 'package:flutter_test/flutter_test.dart';
import 'package:yunan_yanik/main.dart';

void main() {
  testWidgets('Yanık İskambil HD Login screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const YanikIskambilHdApp());
  });
}
