import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snuggletemp/main.dart';

void main() {
  testWidgets('app shell renders', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const SnuggleTemp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
