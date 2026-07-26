import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_reader/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('document metadata survives persistence round trip', () {
    final document = RecentDocument(
      name: 'large.pdf',
      path: '/library/large.pdf',
      openedAt: DateTime.utc(2026, 1, 2),
      documentDate: DateTime.utc(2025, 12, 1),
      fileSize: 250 * 1024 * 1024,
      pageCount: 1200,
      page: 600,
      folder: 'Research',
      isFavorite: true,
    );

    final restored = RecentDocument.fromJson(document.toJson());
    expect(restored.fileSize, 250 * 1024 * 1024);
    expect(restored.pageCount, 1200);
    expect(restored.page, 600);
    expect(restored.folder, 'Research');
    expect(restored.isFavorite, isTrue);
  });

  test('legacy JSON receives safe defaults', () {
    final restored = RecentDocument.fromJson({
      'name': 'legacy.pdf',
      'path': '/legacy.pdf',
      'openedAt': DateTime.utc(2020).toIso8601String(),
    });
    expect(restored.page, 1);
    expect(restored.pageCount, 0);
    expect(restored.fileSize, 0);
    expect(restored.isFavorite, isFalse);
    expect(restored.folder, isNull);
  });

  test('jump-to-page validation accepts only pages inside the PDF', () {
    expect(validPageTarget(' 5 ', 10), 5);
    expect(validPageTarget('0', 10), isNull);
    expect(validPageTarget('11', 10), isNull);
    expect(validPageTarget('abc', 10), isNull);
    expect(validPageTarget('', 10), isNull);
  });

  test('rename changes the private file and preserves metadata', () async {
    final directory = await Directory.systemTemp.createTemp(
      'papertrail-rename-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/old.pdf');
    await source.writeAsBytes([1, 2, 3]);
    final annotations = File('${source.path}.papertrail-annotations.json');
    await annotations.writeAsString('[{"page":1}]');
    final original = RecentDocument(
      name: 'old.pdf',
      path: source.path,
      openedAt: DateTime(2026),
      documentDate: DateTime(2025),
      page: 4,
      pageCount: 10,
      isFavorite: true,
    );
    final renamed = await DocumentStore().rename(original, 'new name');
    expect(renamed.name, 'new name.pdf');
    expect(await File(renamed.path).exists(), isTrue);
    expect(await source.exists(), isFalse);
    expect(
      await File('${renamed.path}.papertrail-annotations.json').readAsString(),
      '[{"page":1}]',
    );
    expect(await annotations.exists(), isFalse);
    expect(renamed.page, 4);
    expect(renamed.isFavorite, isTrue);
  });

  test('case-only rename keeps a valid file path', () async {
    final directory = await Directory.systemTemp.createTemp(
      'papertrail-case-rename-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/report.pdf');
    await source.writeAsBytes([1, 2, 3]);
    final original = RecentDocument(
      name: 'report.pdf',
      path: source.path,
      openedAt: DateTime(2026),
      documentDate: DateTime(2025),
    );

    final renamed = await DocumentStore().rename(original, 'Report');

    expect(renamed.name, 'Report.pdf');
    expect(await File(renamed.path).exists(), isTrue);
    expect(File(renamed.path).path, endsWith('Report.pdf'));
  });

  test('rename reports the sanitized on-disk name', () async {
    final directory = await Directory.systemTemp.createTemp(
      'papertrail-safe-rename-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/old.pdf');
    await source.writeAsBytes([1, 2, 3]);
    final original = RecentDocument(
      name: 'old.pdf',
      path: source.path,
      openedAt: DateTime(2026),
      documentDate: DateTime(2025),
    );

    final renamed = await DocumentStore().rename(original, 'safe:name');

    expect(renamed.name, 'safe_name.pdf');
    expect(renamed.path, endsWith('safe_name.pdf'));
    expect(await File(renamed.path).exists(), isTrue);
  });

  test('annotation rename failure restores the original PDF path', () async {
    final directory = await Directory.systemTemp.createTemp(
      'papertrail-annotation-rollback-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/old.pdf');
    final annotations = File('${source.path}.papertrail-annotations.json');
    await source.writeAsBytes([1, 2, 3]);
    await annotations.writeAsString('[]');
    final document = RecentDocument(
      name: 'old.pdf',
      path: source.path,
      openedAt: DateTime(2026),
      documentDate: DateTime(2026),
    );
    final store = DocumentStore(
      renameOperation: (from, to) async {
        if (from.path.endsWith('.papertrail-annotations.json')) {
          throw const FileSystemException('Injected annotation failure');
        }
        await from.rename(to.path);
      },
    );

    await expectLater(
      store.rename(document, 'new'),
      throwsA(isA<FileSystemException>()),
    );

    expect(await source.exists(), isTrue);
    expect(await File('${directory.path}/new.pdf').exists(), isFalse);
    expect(await annotations.exists(), isTrue);
  });

  test('failed rollback reports the actual on-disk document path', () async {
    final directory = await Directory.systemTemp.createTemp(
      'papertrail-rollback-recovery-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/old.pdf');
    final annotations = File('${source.path}.papertrail-annotations.json');
    await source.writeAsBytes([1, 2, 3]);
    await annotations.writeAsString('[]');
    final document = RecentDocument(
      name: 'old.pdf',
      path: source.path,
      openedAt: DateTime(2026),
      documentDate: DateTime(2026),
    );
    final store = DocumentStore(
      renameOperation: (from, to) async {
        if (from.path.endsWith('.papertrail-annotations.json') ||
            (from.path.endsWith('new.pdf') && to.path.endsWith('old.pdf'))) {
          throw const FileSystemException('Injected rollback failure');
        }
        await from.rename(to.path);
      },
    );

    DocumentRenameException? failure;
    try {
      await store.rename(document, 'new');
    } on DocumentRenameException catch (error) {
      failure = error;
    }

    expect(failure, isNotNull);
    expect(failure!.actualDocument.path, endsWith('new.pdf'));
    expect(await File(failure.actualDocument.path).exists(), isTrue);
    expect(await source.exists(), isFalse);
  });

  test('single-file deletion removes the PDF and annotation sidecar', () async {
    final directory = await Directory.systemTemp.createTemp(
      'papertrail-delete-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final pdf = File('${directory.path}/document.pdf');
    final sidecar = File('${pdf.path}.papertrail-annotations.json');
    await pdf.writeAsBytes([1, 2, 3]);
    await sidecar.writeAsString('[]');
    await deleteDocumentArtifacts(pdf.path);
    expect(await pdf.exists(), isFalse);
    expect(await sidecar.exists(), isFalse);
  });

  test('one damaged record does not hide valid library documents', () async {
    final directory = await Directory.systemTemp.createTemp(
      'papertrail-load-recovery-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final pdf = File('${directory.path}/valid.pdf');
    await pdf.writeAsBytes([1, 2, 3]);
    final valid = RecentDocument(
      name: 'valid.pdf',
      path: pdf.path,
      openedAt: DateTime(2026),
      documentDate: DateTime(2026),
      fileSize: 3,
      pageCount: 1,
      fingerprint: 'known-fingerprint',
    );
    SharedPreferences.setMockInitialValues({
      'recent_documents_v1': '[{"broken":true},${valid.toJsonString()}]',
    });

    final loaded = await DocumentStore().load();

    expect(loaded, hasLength(1));
    expect(loaded.single.name, 'valid.pdf');
  });

  test('crash diagnostics redact PDF paths and passwords', () {
    final sanitized = sanitizeCrashMessage(
      r'Failed C:\private\tax-return.pdf password=Secret123',
    );

    expect(sanitized, isNot(contains('tax-return.pdf')));
    expect(sanitized, isNot(contains('Secret123')));
    expect(sanitized, contains('[PDF]'));
    expect(sanitized, contains('[redacted]'));
  });

  test('temporary cleanup stops at its configured entry budget', () async {
    final directory = await Directory.systemTemp.createTemp(
      'papertrail-bounded-cleanup-',
    );
    addTearDown(() => directory.delete(recursive: true));
    for (var index = 0; index < 8; index++) {
      await File(
        '${directory.path}/papertrail-ocr-$index.png',
      ).writeAsBytes([index]);
    }

    final deleted = await cleanupTemporaryDirectory(
      directory,
      shouldDelete: (_) => true,
      maximumEntries: 3,
      timeLimit: const Duration(seconds: 1),
    );

    expect(deleted, 3);
    expect(await directory.list().length, 5);
  });
}

extension on RecentDocument {
  String toJsonString() => jsonEncode(toJson());
}
