import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qringer_mobile_stream_io/main.dart';

void main() {
  testWidgets('unauthenticated homeowner is routed to sign in', (tester) async {
    await tester.pumpWidget(
      QROnlyApp(
        unauthenticatedHomeBuilder: () => const Scaffold(
          body: Text('Sign in'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Sign in'), findsOneWidget);
  });
}
