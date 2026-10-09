import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/ui/app.dart';

void main() {
  testWidgets('app boots into the recording screen', (tester) async {
    await tester.pumpWidget(const TrackScribeApp());
    await tester.pumpAndSettle();
    expect(find.text('تسجيل'), findsOneWidget);
  });
}
