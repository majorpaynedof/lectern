// Tests for Tidy author names' suggestions. Run with: flutter test
import 'package:flutter_test/flutter_test.dart';
import 'package:lectern/author_tidy.dart';

void main() {
  const library = ['Tom Clancy', 'J. R. R. Tolkien', 'Mercedes Lackey'];

  test('folder name with last name first: merges into the existing author', () {
    final t = suggestAuthorName('Clancy, Tom - Op Center 01', library)!;
    expect(t.name, 'Tom Clancy');
    expect(t.mergeInto, 'Tom Clancy');
    expect(t.confidence, 'High');
  });

  test('several dashes', () {
    expect(suggestAuthorName('Clancy, Tom - Nf - Commanders', library)!.name, 'Tom Clancy');
    expect(suggestAuthorName('Clancy, Tom - Net Force Explorers 11', library)!.name, 'Tom Clancy');
  });

  test('en dash works too', () {
    expect(suggestAuthorName('Clancy, Tom – Op Center 11', library)!.name, 'Tom Clancy');
  });

  test('no existing author: suggested, medium confidence, no merge', () {
    final t = suggestAuthorName('Weber, David - Honor Harrington 03', library)!;
    expect(t.name, 'David Weber');
    expect(t.mergeInto, isNull);
    expect(t.confidence, 'Medium');
  });

  test('plain last name first', () {
    final t = suggestAuthorName('Lackey, Mercedes', library)!;
    expect(t.name, 'Mercedes Lackey');
    expect(t.reason, 'Last name first');
  });

  test('extra text after a normal name', () {
    expect(suggestAuthorName('Tom Clancy - Op Center 02', library)!.name, 'Tom Clancy');
  });

  test('uses the library\'s spelling of initials', () {
    expect(suggestAuthorName('Tolkien, J.R.R.', library)!.name, 'J. R. R. Tolkien');
  });

  test('leaves good names alone', () {
    expect(suggestAuthorName('Tom Clancy', library), isNull);
    expect(suggestAuthorName('Mercedes Lackey', library), isNull);
    expect(suggestAuthorName('Jean-Luc Picard', library), isNull);
  });

  test('never guesses when it isn\'t clearly one person', () {
    expect(suggestAuthorName('Grant, Rob & Marshall, Andrew', library), isNull);
    expect(suggestAuthorName('Rob Grant and Andrew Marshall - Titan', library), isNull);
    expect(suggestAuthorName('King, Jr., Martin Luther', library), isNull);
    expect(suggestAuthorName('Star Wars 2019 - Collection', library), isNull);
  });

  test('companies and suffixes are not "Last, First"', () {
    expect(suggestAuthorName('The DevOps Collective, Inc.', library), isNull);
    expect(suggestAuthorName('Penguin Random House, LLC', library), isNull);
    expect(suggestAuthorName('Smith, Jr.', library), isNull);
    expect(suggestAuthorName('Graphic Audio, Ltd', library), isNull);
  });

  group('same person, different middle initial', () {
    const books = {
      'Steve Pieczenik': 4,
      'Steve R. Pieczenik': 1,
      'Tobias Buckell': 1,
      'Tobias S. Buckell': 1,
      'J. Smith': 2,
      'K. Smith': 3,
    };

    test('merges into the entry with more books, not ticked', () {
      final t = suggestDuplicate('Steve R. Pieczenik', books)!;
      expect(t.mergeInto, 'Steve Pieczenik');
      expect(t.confidence, 'Medium');
      expect(suggestDuplicate('Steve Pieczenik', books), isNull, reason: 'only one side is offered');
    });

    test('on a tie, keeps the name with the initial', () {
      expect(suggestDuplicate('Tobias Buckell', books)!.mergeInto, 'Tobias S. Buckell');
      expect(suggestDuplicate('Tobias S. Buckell', books), isNull);
    });

    test('a surname with different initials is not a duplicate', () {
      expect(suggestDuplicate('J. Smith', books), isNull);
    });
  });
}
