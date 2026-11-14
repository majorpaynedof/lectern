/// Rules for the "there's an update" notice: comparing versions and reading
/// GitHub's latest-release answer. No network here, so it can be tested.
library;

/// A published Lectern release.
class ReleaseInfo {
  const ReleaseInfo({required this.version, required this.url});

  /// e.g. "0.7.2" (no leading "v").
  final String version;

  /// The release page, where the installer is.
  final String url;
}

/// Splits "v0.7.10-beta+19" into numbers [0, 7, 10] and a pre-release tag
/// ("beta"). The build number after "+" is ignored.
({List<int> numbers, String pre}) _parse(String v) {
  var s = v.trim().toLowerCase();
  if (s.startsWith('v')) s = s.substring(1);
  s = s.split('+').first;
  final dash = s.indexOf('-');
  final pre = dash < 0 ? '' : s.substring(dash + 1);
  final core = dash < 0 ? s : s.substring(0, dash);
  final numbers = [for (final p in core.split('.')) int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0];
  return (numbers: numbers, pre: pre);
}

/// Negative if [a] is older than [b], 0 if the same, positive if newer.
/// "0.7.10" is newer than "0.7.9"; "1.0.0-beta" is older than "1.0.0".
int compareVersions(String a, String b) {
  final x = _parse(a);
  final y = _parse(b);
  final len = x.numbers.length > y.numbers.length ? x.numbers.length : y.numbers.length;
  for (var i = 0; i < len; i++) {
    final p = i < x.numbers.length ? x.numbers[i] : 0;
    final q = i < y.numbers.length ? y.numbers[i] : 0;
    if (p != q) return p.compareTo(q);
  }
  if (x.pre == y.pre) return 0;
  if (x.pre.isEmpty) return 1; // a full release beats its pre-release
  if (y.pre.isEmpty) return -1;
  return x.pre.compareTo(y.pre);
}

bool isNewer(String latest, String current) => compareVersions(latest, current) > 0;

/// Reads GitHub's /releases/latest answer. Null for drafts, pre-releases or
/// anything unexpected.
ReleaseInfo? parseLatestRelease(Object? json) {
  if (json is! Map) return null;
  if (json['draft'] == true || json['prerelease'] == true) return null;
  final tag = (json['tag_name'] ?? '').toString().trim();
  final url = (json['html_url'] ?? '').toString().trim();
  if (tag.isEmpty || !RegExp(r'\d').hasMatch(tag)) return null;
  return ReleaseInfo(version: tag.startsWith(RegExp('[vV]')) ? tag.substring(1) : tag, url: url);
}

/// "https://github.com/owner/repo" -> the API address for its latest release.
String? latestReleaseApi(String repoUrl) {
  final m = RegExp(r'github\.com/([^/\s]+)/([^/\s#?]+)').firstMatch(repoUrl);
  if (m == null) return null;
  final repo = m.group(2)!.replaceAll(RegExp(r'\.git$'), '');
  return 'https://api.github.com/repos/${m.group(1)}/$repo/releases/latest';
}
