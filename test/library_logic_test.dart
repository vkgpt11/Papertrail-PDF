import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_reader/library_logic.dart';
import 'package:pdf_reader/main.dart';

RecentDocument document({
  required String name,
  int pages = 1,
  int bytes = 1,
  String? folder,
  DateTime? created,
  DateTime? opened,
}) => RecentDocument(
  name: name,
  path: '/$name',
  openedAt: opened ?? DateTime(2026),
  documentDate: created ?? DateTime(2025),
  pageCount: pages,
  fileSize: bytes,
  folder: folder,
);

void main() {
  test('filters by name, content, folder, date, pages and size', () {
    final item = document(
      name: 'Contract.pdf',
      pages: 20,
      bytes: 5 * 1024 * 1024,
      folder: 'Work',
      created: DateTime(2025, 6),
    );
    expect(
      LibraryFilter(
        query: 'salary',
        folder: 'Work',
        createdAfter: DateTime(2025),
        minimumPages: 10,
        minimumSizeBytes: 1024,
        contentMatchPaths: {item.path},
      ).matches(item),
      isTrue,
    );
    expect(const LibraryFilter(folder: 'Personal').matches(item), isFalse);
    expect(const LibraryFilter(minimumPages: 21).matches(item), isFalse);
  });

  test('all sort modes order documents correctly', () {
    final a = document(
      name: 'A.pdf',
      pages: 2,
      bytes: 10,
      created: DateTime(2024),
      opened: DateTime(2025),
    );
    final b = document(
      name: 'B.pdf',
      pages: 8,
      bytes: 20,
      created: DateTime(2026),
      opened: DateTime(2026),
    );
    expect(compareDocuments(a, b, LibrarySort.nameAscending), lessThan(0));
    expect(compareDocuments(a, b, LibrarySort.nameDescending), greaterThan(0));
    expect(compareDocuments(a, b, LibrarySort.fileSizeLargest), greaterThan(0));
    expect(compareDocuments(a, b, LibrarySort.pageCountMost), greaterThan(0));
    expect(
      compareDocuments(a, b, LibrarySort.documentDateNewest),
      greaterThan(0),
    );
    expect(compareDocuments(a, b, LibrarySort.recentActivity), greaterThan(0));
  });

  test('formats file sizes at unit boundaries', () {
    expect(formatFileSize(12), '12 B');
    expect(formatFileSize(1536), '1.5 KB');
    expect(formatFileSize(2 * 1024 * 1024), '2.0 MB');
  });
}
