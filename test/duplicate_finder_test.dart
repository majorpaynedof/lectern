// Tests for Find duplicates. Run with: flutter test
import 'package:flutter_test/flutter_test.dart';
import 'package:lectern/duplicate_finder.dart';

DupBook b(String id, String title, String author, {double hours = 10, String series = ''}) =>
    DupBook(id: id, title: title, author: author, duration: hours * 3600, series: series);

void main() {
  test('the same title and author (Blood of the Fold twice)', () {
    final g = findDuplicates([
      b('1', 'Blood of the Fold', 'Terry Goodkind', hours: 30),
      b('2', 'Blood of the Fold', 'Terry Goodkind', hours: 30.2),
      b('3', 'Chainfire', 'Terry Goodkind', hours: 25),
    ]);
    expect(g.single.ids, ['1', '2']);
    expect(g.single.confidence, 'High');
  });

  test('a subtitle on one copy (The Two Week Curse)', () {
    final g = findDuplicates([
      b('1', 'The Two Week Curse', 'Michael Chatfield', hours: 12),
      b('2', 'The Two Week Curse: A LitRPG Adventure', 'Michael Chatfield', hours: 12.1),
    ]);
    expect(g.single.ids, ['1', '2']);
    expect(g.single.confidence, 'Medium');
  });

  test('same series and number (The Amazing Maurice)', () {
    final g = findDuplicates([
      b('1', 'The Amazing Maurice and His Educated Rodents', 'Terry Pratchett', hours: 6, series: 'Discworld #28'),
      b('2', 'The Amazing Maurice by Terry Pratchett', 'Terry Pratchett', hours: 6.1, series: 'Discworld #28'),
    ]);
    expect(g.single.ids.length, 2);
    expect(g.single.confidence, 'High');
  });

  test('"by <author>" at the end of a title is ignored', () {
    expect(coreTitle('The Amazing Maurice by Terry Pratchett', 'Terry Pratchett'), 'the amazing maurice');
    expect(coreTitle('Stand by Me', 'Stephen King'), 'stand by me');
  });

  test('a folder-style title ending in the other title', () {
    final g = findDuplicates([
      b('1', '11 ABY - The Jedi Academy Trilogy 02 - Dark Apprentice', 'Kevin J. Anderson', hours: 11.9),
      b('2', 'Dark Apprentice', 'Kevin J. Anderson', hours: 11.8),
    ]);
    expect(g.single.ids.length, 2);
  });

  test('same title, folder name as author, same length: medium', () {
    final g = findDuplicates([
      b('1', 'Dark Apprentice', 'Star Wars', hours: 11.9),
      b('2', 'Dark Apprentice', 'Kevin J. Anderson', hours: 11.9),
    ]);
    expect(g.single.confidence, 'Medium');
  });

  test('abridged and unabridged editions: medium, says why', () {
    final g = findDuplicates([
      b('1', 'Covert One (Abridged)', 'Robert Ludlum', hours: 6),
      b('2', 'Covert One', 'Robert Ludlum', hours: 18),
    ]);
    expect(g.single.confidence, 'Medium');
    expect(g.single.reason, contains('different lengths'));
  });

  group('never flags different books', () {
    test('a sequel', () {
      expect(findDuplicates([b('1', 'Dune', 'Frank Herbert', hours: 21), b('2', 'Dune Messiah', 'Frank Herbert', hours: 8)]),
          isEmpty);
    });

    test('same series, different numbers', () {
      expect(
          findDuplicates([
            b('1', 'Wizard\'s First Rule', 'Terry Goodkind', series: 'Sword of Truth #1'),
            b('2', 'Stone of Tears', 'Terry Goodkind', series: 'Sword of Truth #2'),
          ]),
          isEmpty);
    });

    test('same prefix before a colon, different books', () {
      expect(
          findDuplicates([
            b('1', 'Star Wars: Heir to the Empire', 'Timothy Zahn', hours: 13),
            b('2', 'Star Wars: Dark Force Rising', 'Timothy Zahn', hours: 13),
          ]),
          isEmpty);
    });

    test('same title, different author and length', () {
      expect(findDuplicates([b('1', 'Legacy', 'Author One', hours: 9), b('2', 'Legacy', 'Author Two', hours: 14)]),
          isEmpty);
    });

    test('a pair you said isn\'t a duplicate stays hidden', () {
      final books = [b('1', 'Blood of the Fold', 'Terry Goodkind'), b('2', 'Blood of the Fold', 'Terry Goodkind')];
      expect(findDuplicates(books, ignored: {pairKey('2', '1')}), isEmpty);
    });
  });

  test('three copies make one group', () {
    final g = findDuplicates([
      b('1', 'Chainfire', 'Terry Goodkind'),
      b('2', 'Chainfire', 'Terry Goodkind'),
      b('3', 'Chainfire (Unabridged)', 'Terry Goodkind'),
    ]);
    expect(g.single.ids.toSet(), {'1', '2', '3'});
  });

  group('folders naming different books win (bad matches)', () {
    const sw = '/audiobooks2/Star Wars/Before the Republic, Old Republic era, Rise of the Empire era';
    test('same wrong title, folders with different numbers', () {
      final g = findDuplicates([
        DupBook(id: '1', title: 'Star Wars: Jedi Quest #3: The Dangerous Games', author: 'Jude Watson',
            duration: 8280, path: '$sw/22. 25 BBY - Jedi Quest 04 - The Master of Disguise'),
        DupBook(id: '2', title: 'Star Wars: Jedi Quest #3: The Dangerous Games', author: 'Jude Watson',
            duration: 8400, path: '$sw/21. 27 BBY - Jedi Quest 03 - The Dangerous Games'),
      ]);
      expect(g, isEmpty);
    });

    test('same wrong title, folders with different names', () {
      expect(differentFolders('/x/The Unifying Force', '/x/Force Heretic III Reunion'), isTrue);
    });

    test('real duplicates in similar folders are still found', () {
      final g = findDuplicates([
        DupBook(id: '1', title: 'Blood of the Fold', author: 'Terry Goodkind', duration: 108000,
            path: '/books/Terry Goodkind/Blood of the Fold'),
        DupBook(id: '2', title: 'Blood of the Fold', author: 'Terry Goodkind', duration: 108300,
            path: '/books2/Goodkind, Terry/Blood of the Fold (Unabridged)'),
      ]);
      expect(g.single.ids.length, 2);
    });

    test('a folder with an extra subtitle is still the same book', () {
      expect(differentFolders('/b/The Two Week Curse', '/b/The Two Week Curse - A LitRPG Adventure'), isFalse);
    });
  });

  group('parts and numbered books are different books', () {
    test('Book 1 / Book 2 with the same length', () {
      final g = findDuplicates([
        DupBook(id: '1', title: 'Callista Trilogy - Book 1', author: 'Star Wars', duration: 11040,
            path: '/sw/12 ABY - Children of the Jedi'),
        DupBook(id: '2', title: 'Callista Trilogy - Book 2', author: 'Barbara Hambly', duration: 11100,
            path: '/sw/12 ABY - Darksaber'),
      ]);
      expect(g, isEmpty);
    });

    test('a shared folder prefix alone doesn\'t make two books the same', () {
      expect(differentFolders('/sw/12 ABY - Children of the Jedi', '/sw/12 ABY - Darksaber'), isTrue);
    });

    test('a whole book and parts of a dramatized version', () {
      final g = findDuplicates([
        b('1', 'Elantris', 'Brandon Sanderson', hours: 54.8),
        b('2', 'Elantris (1 of 3) [Dramatized Adaptation]', 'Brandon Sanderson', hours: 6.3),
        b('3', 'Elantris (3 of 3) [Dramatized Adaptation]', 'Brandon Sanderson', hours: 5.9),
        b('4', 'Elantris Part 2', 'Brandon Sanderson', hours: 6.5),
      ]);
      expect(g, isEmpty);
    });

    test('a "Book 3" label on one copy is fine when the lengths match', () {
      final g = findDuplicates([
        b('1', 'All These Worlds: Bobiverse, Book 3', 'Dennis E. Taylor', hours: 9.3),
        b('2', 'All These Worlds', 'Dennis E. Taylor', hours: 9.3),
      ]);
      expect(g.single.ids.length, 2);
    });

    test('part numbers are read from the title', () {
      expect(partNumber('Callista Trilogy - Book 2'), 2);
      expect(partNumber('Elantris (1 of 3)'), 1);
      expect(partNumber('Elantris Part 2'), 2);
      expect(partNumber('Red Dwarf: Titan'), isNull);
    });
  });

  test('two copies in differently named author folders (Red Dwarf: Titan)', () {
    final g = findDuplicates([
      DupBook(id: '1', title: 'Red Dwarf: Titan', author: 'Rob Grant, Andrew Marshall', duration: 39720,
          path: '/audiobooks2/Andrew Marshall Rob Grant/Red Dwarf- Titan'),
      DupBook(id: '2', title: 'Red Dwarf: Titan', author: 'Rob Grant, Andrew Marshall', duration: 39720,
          path: '/audiobooks2/Rob Grant/Red Dwarf Titan'),
    ]);
    expect(g.single.confidence, 'High');
  });
}
