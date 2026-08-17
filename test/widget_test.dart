import 'package:flutter_test/flutter_test.dart';
import 'package:book_dashboard/models.dart';

void main() {
  test('BookSort keyOf and sortStamp', () {
    final b = Book(
      bookId: 'test-1',
      title: 'Sample Book',
      savedAt: 1723700000000,
      openedAt: 1723750000000,
      addedAt: 1723650000000,
      extractedAt: 1723720000000,
    );

    expect(BookSort.savedAt.keyOf(b), 1723700000000);
    expect(BookSort.opened.keyOf(b), 1723750000000);
    expect(BookSort.added.keyOf(b), 1723650000000);
    expect(BookSort.extracted.keyOf(b), 1723720000000);

    expect(sortStamp(b, BookSort.savedAt), '');
    expect(sortStamp(b, BookSort.opened), isNotEmpty);
  });
}
