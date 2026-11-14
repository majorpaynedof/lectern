// Tests for the "new version" notice. Run with: flutter test
import 'package:flutter_test/flutter_test.dart';
import 'package:lectern/update_check.dart';

void main() {
  group('comparing versions', () {
    test('newer patch, minor and major', () {
      expect(isNewer('0.7.2', '0.7.1'), isTrue);
      expect(isNewer('0.8.0', '0.7.9'), isTrue);
      expect(isNewer('1.0.0', '0.9.9'), isTrue);
    });

    test('10 is newer than 9 (numbers, not text)', () {
      expect(isNewer('0.7.10', '0.7.9'), isTrue);
      expect(isNewer('0.7.9', '0.7.10'), isFalse);
    });

    test('same version, with or without "v" and build number', () {
      expect(compareVersions('v0.7.1', '0.7.1'), 0);
      expect(compareVersions('0.7.1+19', '0.7.1'), 0);
      expect(isNewer('v0.7.1', '0.7.1+19'), isFalse);
    });

    test('older is not newer', () => expect(isNewer('0.7.0', '0.7.1'), isFalse));

    test('missing parts count as 0', () {
      expect(compareVersions('0.8', '0.8.0'), 0);
      expect(isNewer('0.8', '0.7.9'), isTrue);
    });

    test('a full release is newer than its pre-release', () {
      expect(isNewer('1.0.0', '1.0.0-beta'), isTrue);
      expect(isNewer('1.0.0-beta', '1.0.0'), isFalse);
    });
  });

  group('reading GitHub\'s answer', () {
    test('a normal release', () {
      final r = parseLatestRelease({
        'tag_name': 'v0.7.2',
        'html_url': 'https://github.com/majorpaynedof/lectern/releases/tag/v0.7.2',
        'draft': false,
        'prerelease': false,
      })!;
      expect(r.version, '0.7.2');
      expect(r.url, endsWith('/v0.7.2'));
    });

    test('drafts, pre-releases and junk are ignored', () {
      expect(parseLatestRelease({'tag_name': 'v0.8.0', 'prerelease': true}), isNull);
      expect(parseLatestRelease({'tag_name': 'v0.8.0', 'draft': true}), isNull);
      expect(parseLatestRelease({'message': 'Not Found'}), isNull);
      expect(parseLatestRelease('nonsense'), isNull);
    });
  });

  test('API address from the repository link', () {
    expect(latestReleaseApi('https://github.com/majorpaynedof/lectern'),
        'https://api.github.com/repos/majorpaynedof/lectern/releases/latest');
    expect(latestReleaseApi('https://github.com/majorpaynedof/lectern.git'),
        'https://api.github.com/repos/majorpaynedof/lectern/releases/latest');
    expect(latestReleaseApi(''), isNull);
  });
}
