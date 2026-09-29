import 'package:flutter_test/flutter_test.dart';

import 'package:local_transfer/main.dart';

void main() {
  testWidgets('the app shell renders its title and empty state', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const LocalTransferApp());

    expect(find.text('Local Transfer'), findsOneWidget);
    expect(find.text('No devices discovered yet.'), findsOneWidget);
  });
}
