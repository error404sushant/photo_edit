import 'package:flutter_test/flutter_test.dart';

import 'package:photo_edit/main.dart';

void main() {
  testWidgets('home screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const PhotoEditApp());
    expect(find.text('PhotoEdit'), findsOneWidget);
    expect(find.text('Open a photo'), findsOneWidget);
  });
}
