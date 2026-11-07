import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api/abs_api.dart';

String formatDuration(double seconds, {bool compact = false}) {
  final s = seconds.isFinite && seconds > 0 ? seconds.round() : 0;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  if (compact) return h > 0 ? '${h}h ${m}m' : '${m}m';
  final mm = m.toString().padLeft(2, '0');
  final ss = sec.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$m:$ss';
}

String stripHtml(String s) => s
    .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n')
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&nbsp;', ' ')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();

String greeting() {
  final h = DateTime.now().hour;
  if (h < 12) return 'Good morning';
  if (h < 18) return 'Good afternoon';
  return 'Good evening';
}


/// An error from an online lookup or a save, in plain words. [service] names
/// what was being asked (e.g. "Google Books"), when known.
String friendlyError(Object e, {String? service}) {
  final who = (service == null || service.trim().isEmpty) ? 'The search service' : service;
  if (e is TimeoutException) {
    return "$who didn't answer in time. It may be busy after a lot of lookups: "
        'try again in a few minutes, or pick another provider.';
  }
  if (e is SocketException || e is http.ClientException) {
    return "Lectern can't reach your server right now. Check the connection and try again.";
  }
  if (e is AbsApiException) {
    final s = e.status ?? 0;
    if (s == 429 || s == 503) return '$who is busy right now. Try again in a few minutes, or pick another provider.';
    if (s >= 500) return '$who had a problem (error $s). Try again later, or pick another provider.';
    if (s == 401 || s == 403) return "Your account isn't allowed to do that (error $s).";
    if (s == 404) return 'Not found on the server.';
  }
  return '$e';
}
