import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_reader/pdf_password_prompt.dart';

void main() {
  Future<void> openPrompt(
    WidgetTester tester, {
    required ValueChanged<PdfPasswordPromptResult?> onResult,
    bool incorrectPassword = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async => onResult(
              await showDialog<PdfPasswordPromptResult>(
                context: context,
                barrierDismissible: false,
                builder: (_) => PdfPasswordPromptDialog(
                  incorrectPassword: incorrectPassword,
                ),
              ),
            ),
            child: const Text('Show'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
  }

  testWidgets('requires a non-empty password', (tester) async {
    await openPrompt(tester, onResult: (_) {});
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Open'))
          .onPressed,
      isNull,
    );

    await tester.enterText(find.byType(TextField), 'secret');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Open'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('shows feedback after an incorrect password', (tester) async {
    await openPrompt(tester, incorrectPassword: true, onResult: (_) {});
    expect(find.text('Incorrect password. Try again.'), findsOneWidget);
  });

  testWidgets('returns the password entered by the user', (tester) async {
    PdfPasswordPromptResult? result;
    await openPrompt(tester, onResult: (value) => result = value);
    await tester.enterText(find.byType(TextField), 'correct-password');
    await tester.pump();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(result?.cancelled, isFalse);
    expect(result?.password, 'correct-password');
  });

  testWidgets('returns an explicit cancellation result', (tester) async {
    PdfPasswordPromptResult? result;
    await openPrompt(tester, onResult: (value) => result = value);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result?.cancelled, isTrue);
    expect(result?.password, isNull);
  });
}
