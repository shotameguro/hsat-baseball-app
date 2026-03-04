import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_yakyu_app/main.dart';

void main() {
  testWidgets('App load test', (WidgetTester tester) async {
    // YakyuAppとしてアプリを起動するテストに変更します
    await tester.pumpWidget(const MaterialApp(home: YakyuApp()));

    // 「選手」という文字が画面にあるか確認
    expect(find.textContaining('選手'), findsOneWidget);
  });
}