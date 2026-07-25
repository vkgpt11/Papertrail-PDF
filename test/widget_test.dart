import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_reader/main.dart';
import 'package:pdf_reader/horizontal_scroll_cue.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> prepareApp(WidgetTester tester, Size size) async {
  SharedPreferences.setMockInitialValues({});
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('com.papertrail.pdfreader/open_pdf'),
        (_) async => null,
      );
  await tester.pumpWidget(const PapertrailApp());
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.papertrail.pdfreader/open_pdf'),
          null,
        );
  });

  for (final entry in {
    'small phone': const Size(320, 568),
    'modern phone': const Size(390, 844),
    'tablet landscape': const Size(1280, 800),
  }.entries) {
    testWidgets('library renders without overflow on ${entry.key}', (
      tester,
    ) async {
      await prepareApp(tester, entry.value);
      expect(find.text('Papertrail'), findsOneWidget);
      expect(find.byTooltip('Sort PDFs'), findsOneWidget);
      expect(find.byTooltip('Change theme'), findsOneWidget);
      expect(find.byTooltip('Search filters'), findsNothing);
      expect(find.byTooltip('Create library folder'), findsNothing);
      expect(tester.takeException(), isNull);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  testWidgets('theme control changes app brightness', (tester) async {
    await prepareApp(tester, const Size(390, 844));
    final before = tester
        .widget<MaterialApp>(find.byType(MaterialApp))
        .themeMode;
    await tester.tap(find.byTooltip('Change theme'));
    await tester.pump(const Duration(milliseconds: 100));
    final after = tester
        .widget<MaterialApp>(find.byType(MaterialApp))
        .themeMode;
    expect(after, isNot(before));
  });

  testWidgets('bottom page controls are configurable and default off', (
    tester,
  ) async {
    await prepareApp(tester, const Size(390, 844));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('show_bottom_page_controls'), isNull);

    tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('Done'), findsNothing);
    expect(find.text('Bottom page controls'), findsOneWidget);
    final pageControlTile = find.widgetWithText(
      SwitchListTile,
      'Bottom page controls',
    );
    final pageControlSwitch = find.descendant(
      of: pageControlTile,
      matching: find.byType(Switch),
    );
    expect(tester.widget<Switch>(pageControlSwitch).value, isFalse);
    final magnifierSwitch = find.descendant(
      of: find.widgetWithText(SwitchListTile, 'Text selection magnifier'),
      matching: find.byType(Switch),
    );
    expect(tester.widget<Switch>(magnifierSwitch).value, isFalse);
    final messageSwitch = find.descendant(
      of: find.widgetWithText(SwitchListTile, 'In-app messages'),
      matching: find.byType(Switch),
    );
    expect(tester.widget<Switch>(messageSwitch).value, isTrue);
    await tester.tap(find.text('Header options'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final sortHeaderSwitch = find.descendant(
      of: find.widgetWithText(SwitchListTile, 'Sort PDFs'),
      matching: find.byType(Switch),
    );
    final filterHeaderSwitch = find.descendant(
      of: find.widgetWithText(SwitchListTile, 'Search filters'),
      matching: find.byType(Switch),
    );
    expect(tester.widget<Switch>(sortHeaderSwitch).value, isTrue);
    expect(tester.widget<Switch>(filterHeaderSwitch).value, isFalse);
    await tester.tap(find.text('Header options'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Search document'), findsNothing);
    final drawerScrollable = find.descendant(
      of: find.byType(Drawer),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('Reader options'),
      300,
      scrollable: drawerScrollable,
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Reader options'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final searchToolSwitch = find.descendant(
      of: find.widgetWithText(SwitchListTile, 'Search document'),
      matching: find.byType(Switch),
    );
    final annotationToolSwitch = find.descendant(
      of: find.widgetWithText(SwitchListTile, 'Annotation tools'),
      matching: find.byType(Switch),
    );
    expect(tester.widget<Switch>(searchToolSwitch).value, isTrue);
    expect(tester.widget<Switch>(annotationToolSwitch).value, isFalse);

    await tester.tap(pageControlSwitch);
    await tester.pump();
    expect(prefs.getBool('show_bottom_page_controls'), isTrue);
    await tester.tap(magnifierSwitch);
    await tester.pump();
    expect(prefs.getBool('text_selection_magnifier'), isTrue);
    await tester.tap(messageSwitch);
    await tester.pump();
    expect(prefs.getBool('show_in_app_messages'), isFalse);
  });

  testWidgets('only essential sorting options are enabled by default', (
    tester,
  ) async {
    await prepareApp(tester, const Size(390, 844));
    await tester.tap(find.byTooltip('Sort PDFs'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Name: A to Z'), findsOneWidget);
    expect(find.text('Recent activity'), findsOneWidget);
    expect(find.text('Document date: newest'), findsOneWidget);
    expect(find.text('Name: Z to A'), findsNothing);
    expect(find.text('File size: largest'), findsNothing);
    expect(find.text('Page count: most'), findsNothing);
  });

  testWidgets('horizontal cue reveals additional content in both directions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 120,
            height: 60,
            child: HorizontalScrollCue(
              builder: (controller) => ListView(
                controller: controller,
                scrollDirection: Axis.horizontal,
                children: List.generate(
                  4,
                  (index) => SizedBox(width: 100, child: Text('Item $index')),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);
    await tester.drag(find.byType(ListView), const Offset(-180, 0));
    await tester.pump();
    expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);
  });
}
