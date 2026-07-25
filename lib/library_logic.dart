import 'main.dart';

class LibraryFilter {
  const LibraryFilter({
    this.query = '',
    this.folder,
    this.createdAfter,
    this.minimumPages = 0,
    this.minimumSizeBytes = 0,
    this.contentMatchPaths = const {},
  });

  final String query;
  final String? folder;
  final DateTime? createdAfter;
  final int minimumPages;
  final int minimumSizeBytes;
  final Set<String> contentMatchPaths;

  bool matches(RecentDocument document) {
    final normalized = query.trim().toLowerCase();
    return (normalized.isEmpty ||
            document.name.toLowerCase().contains(normalized) ||
            contentMatchPaths.contains(document.path)) &&
        (folder == null || document.folder == folder) &&
        (createdAfter == null ||
            document.documentDate.isAfter(createdAfter!)) &&
        document.pageCount >= minimumPages &&
        document.fileSize >= minimumSizeBytes;
  }
}

int compareDocuments(
  RecentDocument a,
  RecentDocument b,
  LibrarySort sort,
) => switch (sort) {
  LibrarySort.nameAscending => a.name.toLowerCase().compareTo(
    b.name.toLowerCase(),
  ),
  LibrarySort.nameDescending => b.name.toLowerCase().compareTo(
    a.name.toLowerCase(),
  ),
  LibrarySort.recentActivity => b.openedAt.compareTo(a.openedAt),
  LibrarySort.documentDateNewest => b.documentDate.compareTo(a.documentDate),
  LibrarySort.documentDateOldest => a.documentDate.compareTo(b.documentDate),
  LibrarySort.fileSizeLargest => b.fileSize.compareTo(a.fileSize),
  LibrarySort.fileSizeSmallest => a.fileSize.compareTo(b.fileSize),
  LibrarySort.pageCountMost => b.pageCount.compareTo(a.pageCount),
  LibrarySort.pageCountFewest => a.pageCount.compareTo(b.pageCount),
};

String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
