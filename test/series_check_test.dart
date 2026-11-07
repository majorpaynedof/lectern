// Tests for Check series. Run with: flutter test
import 'package:flutter_test/flutter_test.dart';
import 'package:lectern/series_check.dart';

void main() {
  group('reading the server\'s series text', () {
    test('one series with a number', () {
      expect(parseSeries('Bobiverse #3'), [(name: 'Bobiverse', sequence: '3')]);
    });

    test('several series, decimals, no number', () {
      expect(parseSeries('Star Wars #55, Thrawn Trilogy #1.5, Legends'), [
        (name: 'Star Wars', sequence: '55'),
        (name: 'Thrawn Trilogy', sequence: '1.5'),
        (name: 'Legends', sequence: ''),
      ]);
    });

    test('empty', () => expect(parseSeries(''), isEmpty));
  });

  test('1, 01 and 1.0 are the same number', () {
    expect(sameSequence('1', '01'), isTrue);
    expect(sameSequence('1', '1.0'), isTrue);
    expect(sameSequence('1', '1.5'), isFalse);
  });

  group('comparing with what was found online', () {
    test('missing number is filled in', () {
      final f = checkBookSeries([(name: 'Bobiverse', sequence: '')], [(name: 'Bobiverse', sequence: '3')]);
      expect(f.single.issue, SeriesIssue.numberMissing);
      expect(f.single.to, '3');
    });

    test('a different number is offered', () {
      final f = checkBookSeries([(name: 'Bobiverse', sequence: '2')], [(name: 'Bobiverse', sequence: '3')]);
      expect(f.single.issue, SeriesIssue.numberDifferent);
      expect(f.single.describe, 'Bobiverse: #2 → #3');
    });

    test('the same number written differently is fine', () {
      expect(checkBookSeries([(name: 'Op-Center', sequence: '01')], [(name: 'Op-Center', sequence: '1')]), isEmpty);
    });

    test('series names that differ slightly still match', () {
      final f = checkBookSeries([(name: 'Op Center', sequence: '')], [(name: 'Op-Center', sequence: '4')]);
      expect(f, isNotEmpty);
    });

    test('a series online that you don\'t have the book in is ignored', () {
      expect(checkBookSeries([(name: 'Star Wars', sequence: '1')], [(name: 'Thrawn', sequence: '2')]), isEmpty);
    });

    test('nothing found online: nothing to change', () {
      expect(checkBookSeries([(name: 'Star Wars', sequence: '1')], const []), isEmpty);
    });
  });

  test('two books with the same number in one series', () {
    final d = findDuplicateNumbers({
      'a': [(name: 'Op-Center', sequence: '1')],
      'b': [(name: 'op-center', sequence: '01')],
      'c': [(name: 'Op-Center', sequence: '2')],
      'd': [(name: 'Bobiverse', sequence: '1')],
    });
    expect(d.keys, ['Op-Center']);
    expect(d['Op-Center']!.values.single, ['a', 'b']);
  });
}
