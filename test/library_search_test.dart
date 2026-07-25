import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_reader/library_search.dart';

void main() {
  test('search returns page number and bounded snippet', () async {
    final directory = await Directory.systemTemp.createTemp('papertrail-test-');
    addTearDown(() => directory.delete(recursive: true));
    final index = LibrarySearchIndex(
      indexFile: File('${directory.path}/index.json'),
    );
    await index.indexTextPages('/a.pdf', [
      'First page',
      'The quick brown fox contains the target phrase for testing.',
    ]);
    final hits = await index.search('target phrase');
    expect(hits, hasLength(1));
    expect(hits.single.path, '/a.pdf');
    expect(hits.single.page, 2);
    expect(hits.single.snippet, contains('target phrase'));
  });

  test('search is case-insensitive and index entries can be removed', () async {
    final directory = await Directory.systemTemp.createTemp('papertrail-test-');
    addTearDown(() => directory.delete(recursive: true));
    final index = LibrarySearchIndex(
      indexFile: File('${directory.path}/index.json'),
    );
    await index.indexTextPages('/a.pdf', ['CONFIDENTIAL']);
    expect(await index.search('confidential'), hasLength(1));
    await index.remove('/a.pdf');
    expect(await index.search('confidential'), isEmpty);
  });

  test('indexed pages move atomically when a PDF is renamed', () async {
    final directory = await Directory.systemTemp.createTemp('papertrail-test-');
    addTearDown(() => directory.delete(recursive: true));
    final index = LibrarySearchIndex(
      indexFile: File('${directory.path}/index.json'),
    );
    await index.indexTextPages('/old.pdf', ['Important indexed text']);
    expect(await index.contains('/old.pdf'), isTrue);
    await index.rename('/old.pdf', '/new.pdf');
    expect(await index.contains('/old.pdf'), isFalse);
    expect(await index.contains('/new.pdf'), isTrue);
    expect((await index.search('indexed')).single.path, '/new.pdf');
  });

  test('serialized updates do not lose concurrent index entries', () async {
    final directory = await Directory.systemTemp.createTemp('papertrail-test-');
    addTearDown(() => directory.delete(recursive: true));
    final index = LibrarySearchIndex(
      indexFile: File('${directory.path}/index.json'),
    );
    await Future.wait([
      index.indexTextPages('/one.pdf', ['one']),
      index.indexTextPages('/two.pdf', ['two']),
      index.indexTextPages('/three.pdf', ['three']),
    ]);
    expect(await index.contains('/one.pdf'), isTrue);
    expect(await index.contains('/two.pdf'), isTrue);
    expect(await index.contains('/three.pdf'), isTrue);
  });
}
