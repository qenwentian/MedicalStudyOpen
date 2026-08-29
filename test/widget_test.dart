import 'package:flutter_test/flutter_test.dart';
import 'package:anatomy_atlas/main.dart';

void main() {
  testWidgets('App launches with AtlasScreen', (WidgetTester tester) async {
    await tester.pumpWidget(const AnatomyAtlasApp());

    // Verify the app title is rendered in the top bar overlay.
    expect(find.text('Anatomy Atlas'), findsOneWidget);
  });
}
