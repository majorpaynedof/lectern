import 'dart:async';
import 'dart:convert';

/// Keeps your place in a book in step with the server, and makes sure an
/// out-of-date position from this PC never replaces a newer one from another
/// device.
///
/// Every save goes through here. The rules:
///
/// 1. **Check before sending.** After opening a book, a pause, the PC
///    sleeping or a failed save, nothing is sent until the server has been
///    checked. ([hold] closes the gate; a successful [check] opens it.)
/// 2. **Another device wins until you choose.** The keeper remembers the
///    position the server last had from this PC ([base]). If the server now
///    has something else, another device saved it. If that's a different
///    spot from where you are, [conflict] is set and nothing is sent until
///    [resolve]. No clocks are compared, so a PC clock that's off can't fool
///    it.
/// 3. **Never backwards by accident.** A save more than
///    [backwardsAllowance] seconds behind [base] is refused unless you
///    went there yourself ([userSeeked]).
/// 4. **Local first.** A save is written to [UnsentStore] before it's sent
///    and removed once the server has it, so a dropped connection, a crash
///    or closing the app while offline never loses your place. It's sent
///    later only if the server hasn't moved on in the meantime.
/// 5. **Only real playback counts.** Positions the player isn't sure of
///    (`trusted: false`) are never saved.
///
/// Everything here is plain Dart with the server and storage passed in, so
/// it can be tested without a player or a network (see test/).
class ProgressKeeper {
  ProgressKeeper({
    required this.store,
    DateTime Function()? now,
    Future<void> Function(Duration)? delay,
    void Function(String)? log,
  })  : _now = now ?? DateTime.now,
        _delay = delay ?? Future<void>.delayed,
        _log = log ?? ((_) {});

  final UnsentStore store;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _delay;
  final void Function(String) _log;

  /// Called whenever [conflict], [problem], [lastSavedAt] or the gate change.
  void Function()? onChange;

  /// Two positions this close (seconds) count as the same place.
  static const sameSpot = 10.0;

  /// How far behind [base] a save may be without you having gone back
  /// yourself (seconds).
  static const backwardsAllowance = 30.0;

  static const problemUnreachable =
      'Lectern can\'t reach the server right now. Your place is kept on this PC '
      'and will be saved once Lectern has checked the server.';
  static const problemFailing =
      'Your listening position isn\'t reaching the server. It\'s kept on this PC '
      'and Lectern will keep trying.';
  static const problemBackwards =
      'Lectern stopped a save that would have moved your place backwards. '
      'If you meant to go back, pick the spot again from the chapter list.';

  ProgressServer? _server;
  String? _itemId;
  String? _sessionId;
  double _duration = 0;

  double _base = 0;
  bool _gateOpen = false;
  String _holdReason = '';
  UnsentSave? _unsent;
  double _listened = 0;
  double? _allowBackTo;
  Future<void> _queue = Future.value();

  /// The server's position from another device, when it differs from where
  /// you are. Nothing is sent until [resolve].
  ServerProgress? conflict;

  /// A later position this PC played while offline, when the server has an
  /// earlier one saved by another device since. Offered, never used by itself.
  double? offlineSpot;

  /// A message for the warning banner, or null.
  String? problem;

  /// When the server last accepted a position from this PC.
  DateTime? lastSavedAt;

  /// Saves in a row that couldn't reach the server.
  int failedSaves = 0;

  bool get active => _itemId != null;
  bool get gateOpen => _gateOpen;

  /// The position the server has as far as this PC knows.
  double get base => _base;

  /// A position played on this PC that the server doesn't have yet.
  UnsentSave? get unsent => _unsent;
  double get listened => _listened;
  String? get sessionId => _sessionId;

  // ------------------------------------------------------------ lifecycle

  /// Starts keeping a book that was just opened. [serverPosition] is where
  /// the server said you are (the play request returns it, so it's fresh).
  ///
  /// Returns where playback should start: [serverPosition], or further on
  /// if this PC played further last time but couldn't save it and no other
  /// device has saved since.
  Future<double> begin({
    required ProgressServer server,
    required String itemId,
    required String sessionId,
    required double duration,
    required double serverPosition,
  }) =>
      _serial(() async {
        _server = server;
        _itemId = itemId;
        _sessionId = sessionId;
        _duration = duration;
        _base = serverPosition;
        _gateOpen = true; // the server's position was just read
        _holdReason = '';
        _unsent = null;
        _listened = 0;
        _allowBackTo = null;
        conflict = null;
        offlineSpot = null;
        problem = null;
        failedSaves = 0;

        final left = await _loadUnsent(itemId);
        if (left == null) return serverPosition;
        if ((serverPosition - left.position).abs() <= sameSpot) {
          // It reached the server after all.
          await _clearStore(itemId);
          return serverPosition;
        }
        if ((serverPosition - left.basePosition).abs() > sameSpot) {
          await _clearStore(itemId);
          if (left.position > serverPosition + sameSpot) {
            // The server went *backwards* meanwhile (another app saving an
            // old position, or you rewound there). Don't guess: offer it.
            _log('Another device saved ${_s(serverPosition)} since; offering the later spot '
                '${_s(left.position)} from this PC.');
            offlineSpot = left.position;
            _changed();
          } else {
            _log('Not using the unsaved position ${_s(left.position)} from last time: '
                'another device saved ${_s(serverPosition)} since.');
          }
          return serverPosition;
        }
        _log('Carrying on from ${_s(left.position)}: played on this PC last time but not saved yet.');
        _listened = left.listened;
        _unsent = left.copyWith(sessionId: sessionId);
        await _send();
        _changed();
        return left.position;
      });

  /// Stops keeping the current book without saving (use [close] to save).
  void end() {
    _itemId = null;
    _sessionId = null;
    _server = null;
    _unsent = null;
    _listened = 0;
    conflict = null;
    offlineSpot = null;
    problem = null;
    _gateOpen = false;
  }

  /// The listening session changed (a new one was started for this book).
  void updateSession(String sessionId) => _sessionId = sessionId;

  void addListened(double seconds) {
    if (active) _listened += seconds;
  }

  /// You moved to [position] yourself, so going back there is fine.
  void userSeeked(double position) {
    if (position < _base - backwardsAllowance) _allowBackTo = position;
  }

  // ------------------------------------------------------------ the gate

  /// Stop sending until the server has been checked again: on pause, when
  /// the PC wakes from sleep, or when the connection drops.
  void hold(String reason) {
    if (!active || !_gateOpen) return;
    _gateOpen = false;
    _holdReason = reason;
    _log('Holding saves until the server is checked ($reason).');
    _changed();
  }

  /// Reopen after a very short pause without checking the server. Only
  /// undoes a pause hold: a hold for sleep or a dropped connection stays.
  void releasePause() {
    if (!active || _gateOpen || conflict != null || _holdReason != 'paused') return;
    _gateOpen = true;
    _holdReason = '';
  }

  /// Looks at the server's position and decides whether this PC can carry
  /// on saving. With [patient], keeps trying for [patience] when the server
  /// can't be reached (the network often takes a few seconds after sleep).
  Future<CheckResult> check({
    required double localPosition,
    bool patient = false,
    Duration patience = const Duration(seconds: 20),
  }) =>
      _serial(() => _check(localPosition, patient ? patience : Duration.zero));

  Future<CheckResult> _check(double local, Duration patience) async {
    final server = _server;
    final itemId = _itemId;
    if (server == null || itemId == null) return CheckResult.unreachable;
    if (conflict != null) return CheckResult.otherDeviceAhead;

    final giveUp = _now().add(patience);
    ServerProgress? remote;
    var tries = 0;
    while (true) {
      tries++;
      try {
        remote = await server.fetch(itemId);
        if (tries > 1) _log('Reached the server after $tries tries.');
        if (_unreachableInRow > 0) _log('Server reachable again.');
        _unreachableInRow = 0;
        break;
      } on ServerRejected catch (e) {
        _log('Could not check the server position: $e');
        return _unreachable();
      } catch (e) {
        if (!_now().isBefore(giveUp) || _itemId != itemId) {
          // The full error once; after that, a short note so the log stays readable.
          _log(_unreachableInRow == 0
              ? 'Could not check the server position: $e'
              : 'Server still not reachable (${_unreachableInRow + 1} checks in a row).');
          return _unreachable();
        }
        if (tries == 1) _log('Server not reachable yet; retrying...');
        await _delay(const Duration(seconds: 2));
      }
    }
    if (_itemId != itemId) return CheckResult.unreachable;

    final unsent = _unsent;
    if (remote == null || (remote.currentTime - _base).abs() <= sameSpot) {
      // The server still has what this PC last gave it.
    } else if (unsent != null && (remote.currentTime - unsent.position).abs() <= sameSpot) {
      // Our last save arrived even though we didn't hear back.
      _base = remote.currentTime;
      _unsent = null;
      await _clearStore(itemId);
    } else {
      // Another device saved since.
      _log('Another device saved ${_s(remote.currentTime)} (this PC last saved ${_s(_base)}, '
          'is at ${_s(local)}).');
      _base = remote.currentTime;
      _allowBackTo = null;
      if (unsent != null) {
        _unsent = null; // out of date now; listening time is kept
        await _clearStore(itemId);
      }
      if ((remote.currentTime - local).abs() > sameSpot) {
        conflict = remote;
        _changed();
        return CheckResult.otherDeviceAhead;
      }
    }

    if (!_gateOpen) _log('Server checked: no other device has saved since; saving again.');
    _gateOpen = true;
    _holdReason = '';
    if (problem == problemUnreachable) problem = null;
    _changed();
    if (_unsent != null) await _send();
    return CheckResult.clear;
  }

  int _unreachableInRow = 0;

  CheckResult _unreachable() {
    _unreachableInRow++;
    // Not a pause hold any more: only a successful check reopens it.
    _holdReason = 'server not reachable';
    problem ??= problemUnreachable;
    _changed();
    return CheckResult.unreachable;
  }

  /// Your answer to [conflict]: [jump] to the other device's position, or
  /// stay at [localPosition] (which is then saved).
  Future<void> resolve({required bool jump, required double localPosition}) => _serial(() async {
        final c = conflict;
        if (c == null || !active) return;
        conflict = null;
        _gateOpen = true;
        _holdReason = '';
        _base = c.currentTime;
        if (jump) {
          _allowBackTo = null;
          _log('Jumping to the other device\'s position ${_s(c.currentTime)}.');
        } else {
          _allowBackTo = localPosition;
          _log('Staying at ${_s(localPosition)} instead of the other device\'s ${_s(c.currentTime)}.');
          await _keep(localPosition);
          await _send();
        }
        _changed();
      });

  // ------------------------------------------------------------ saving

  /// Saves [position]: every 15 s while playing, and on pause. [trusted] is
  /// whether the player is sure it's really playing there.
  Future<SaveResult> save(double position, {required bool trusted}) => _serial(() async {
        if (!active) return SaveResult.inactive;
        if (!trusted) return SaveResult.untrusted;
        if (conflict != null) return SaveResult.waitingForChoice;
        if (_isBackwards(position)) return SaveResult.blockedBackwards;
        await _keep(position);
        if (!_gateOpen) {
          final r = await _check(position, Duration.zero);
          if (r == CheckResult.otherDeviceAhead) return SaveResult.waitingForChoice;
          if (r == CheckResult.unreachable) return SaveResult.keptOnThisPc;
          return _unsent == null ? SaveResult.sent : SaveResult.keptOnThisPc;
        }
        return _send();
      });

  /// Closing the book: saves [position] if [trusted] and it's safe, then
  /// ends the listening session. If the server can't be reached the
  /// position stays on this PC for next time.
  Future<void> close(double position, {required bool trusted}) => _serial(() async {
        final server = _server;
        final itemId = _itemId;
        final sessionId = _sessionId;
        if (server == null || itemId == null || sessionId == null) return;

        if (trusted && conflict == null && !_isBackwards(position)) await _keep(position);
        if (!_gateOpen && conflict == null) {
          await _check(position, const Duration(seconds: 5));
        }

        final c = conflict;
        final u = _unsent;
        try {
          if (c != null) {
            // Keep the other device's position; only listening time is sent.
            await server.close(sessionId, currentTime: c.currentTime, listened: _listened, duration: _duration);
            _log('Closed without changing the other device\'s position.');
          } else if (_gateOpen && u != null) {
            try {
              await server.close(sessionId, currentTime: u.position, listened: _listened, duration: _duration);
            } on ServerRejected {
              await server.put(itemId, currentTime: u.position, duration: _duration);
            }
            _base = u.position;
            _unsent = null;
            await _clearStore(itemId);
            lastSavedAt = _now();
            _log('Closed at ${_s(u.position)}.');
          } else if (_gateOpen) {
            // Nothing trustworthy to save: close with the server's own position.
            final keep = await server.fetch(itemId);
            if (keep != null) {
              await server.close(sessionId, currentTime: keep.currentTime, listened: 0, duration: _duration);
            }
            _log('Closed without saving a position (playback wasn\'t confirmed).');
          } else if (u != null) {
            _log('Server not reachable: keeping ${_s(u.position)} on this PC for next time.');
          }
        } catch (e) {
          _log('Could not close the listening session: $e'
              '${_unsent != null ? '; your place is kept on this PC for next time' : ''}.');
        }
        end();
        _changed();
      });

  bool _isBackwards(double position) {
    if (position >= _base - backwardsAllowance) return false;
    final allowed = _allowBackTo;
    if (allowed != null && position >= allowed - 5) return false;
    _log('Refusing to save ${_s(position)}: that\'s behind the saved ${_s(_base)} and you didn\'t go back yourself.');
    problem ??= problemBackwards;
    _changed();
    return true;
  }

  Future<void> _keep(double position) async {
    final u = UnsentSave(
      itemId: _itemId!,
      sessionId: _sessionId!,
      position: position,
      basePosition: _base,
      duration: _duration,
      listened: _listened,
    );
    _unsent = u;
    try {
      await store.write(u);
    } catch (e) {
      _log('Could not keep the position on this PC: $e');
    }
  }

  Future<SaveResult> _send() async {
    final server = _server;
    final u = _unsent;
    if (server == null || u == null) return SaveResult.inactive;
    final listened = _listened;
    final sessionId = _sessionId ?? u.sessionId;
    var sentListening = true;
    try {
      try {
        await server.sync(sessionId, currentTime: u.position, listened: listened, duration: _duration);
      } on ServerRejected catch (e) {
        // Usually the server no longer knows this session (it restarted).
        // Save the position directly, then carry on in a new session.
        _log('Save rejected ($e); saving the position directly.');
        await server.put(u.itemId, currentTime: u.position, duration: _duration);
        sentListening = false;
        final fresh = await server.renewSession(u.itemId);
        if (fresh != null && _itemId == u.itemId) {
          _sessionId = fresh;
          _log('Started a new listening session $fresh.');
        }
      }
    } on ServerRejected catch (e) {
      _log('Progress save failed: $e');
      return _failed();
    } catch (e) {
      _log('Progress save failed (${failedSaves + 1} in a row): $e');
      hold('save failed');
      return _failed();
    }

    if (failedSaves > 0) {
      _log('Saved ${_s(u.position)} (working again after $failedSaves failed attempts).');
    } else {
      _log('Saved ${_s(u.position)}.');
    }
    failedSaves = 0;
    if (problem == problemFailing || problem == problemUnreachable || problem == problemBackwards) {
      problem = null;
    }
    _base = u.position;
    _allowBackTo = null;
    if (identical(_unsent, u)) _unsent = null;
    if (sentListening) _listened = (_listened - listened).clamp(0.0, double.infinity);
    lastSavedAt = _now();
    await _clearStore(u.itemId);
    _changed();
    return SaveResult.sent;
  }

  SaveResult _failed() {
    failedSaves++;
    if (failedSaves >= 3) problem = problemFailing;
    _changed();
    return SaveResult.keptOnThisPc;
  }

  // ------------------------------------------------------------ helpers

  Future<UnsentSave?> _loadUnsent(String itemId) async {
    try {
      return await store.load(itemId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _clearStore(String itemId) async {
    try {
      await store.clear(itemId);
    } catch (_) {}
  }

  Future<T> _serial<T>(Future<T> Function() f) {
    final done = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        done.complete(await f());
      } catch (e, st) {
        done.completeError(e, st);
      }
    });
    return done.future;
  }

  void _changed() => onChange?.call();

  static String _s(double seconds) => '${seconds.toStringAsFixed(0)} s';
}

enum CheckResult { clear, otherDeviceAhead, unreachable }

enum SaveResult { sent, keptOnThisPc, untrusted, waitingForChoice, blockedBackwards, inactive }

class ServerProgress {
  const ServerProgress(this.currentTime, this.lastUpdate);
  final double currentTime;
  final int lastUpdate;
}

/// The server answered, but with an error. (Anything else thrown by a
/// [ProgressServer] means it couldn't be reached.)
class ServerRejected implements Exception {
  ServerRejected(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The server calls the keeper needs.
abstract class ProgressServer {
  /// The server's position for a book, or null if it has none.
  Future<ServerProgress?> fetch(String itemId);
  Future<void> sync(String sessionId, {required double currentTime, required double listened, required double duration});
  Future<void> close(String sessionId, {required double currentTime, required double listened, required double duration});

  /// Saves a position without a listening session.
  Future<void> put(String itemId, {required double currentTime, required double duration});

  /// Starts a new listening session for the book; returns its id.
  Future<String?> renewSession(String itemId);
}

/// A position played on this PC that the server doesn't have yet.
class UnsentSave {
  const UnsentSave({
    required this.itemId,
    required this.sessionId,
    required this.position,
    required this.basePosition,
    required this.duration,
    required this.listened,
  });

  final String itemId;
  final String sessionId;
  final double position;

  /// What the server had when this was played. If the server has something
  /// else by the time it's sent, another device saved since and this one is
  /// dropped.
  final double basePosition;
  final double duration;
  final double listened;

  UnsentSave copyWith({String? sessionId}) => UnsentSave(
        itemId: itemId,
        sessionId: sessionId ?? this.sessionId,
        position: position,
        basePosition: basePosition,
        duration: duration,
        listened: listened,
      );

  Map<String, dynamic> toJson() => {
        'itemId': itemId,
        'sessionId': sessionId,
        'position': position,
        'basePosition': basePosition,
        'duration': duration,
        'listened': listened,
      };

  static UnsentSave? fromJson(Object? j) {
    if (j is! Map) return null;
    final itemId = j['itemId'];
    final position = j['position'];
    final base = j['basePosition'];
    if (itemId is! String || position is! num || base is! num) return null;
    return UnsentSave(
      itemId: itemId,
      sessionId: j['sessionId'] as String? ?? '',
      position: position.toDouble(),
      basePosition: base.toDouble(),
      duration: (j['duration'] as num?)?.toDouble() ?? 0,
      listened: (j['listened'] as num?)?.toDouble() ?? 0,
    );
  }

  String encode() => jsonEncode(toJson());
  static UnsentSave? decode(String s) {
    try {
      return fromJson(jsonDecode(s));
    } catch (_) {
      return null;
    }
  }
}

/// Where unsent positions are kept (on disk in the app, in memory in tests).
abstract class UnsentStore {
  Future<UnsentSave?> load(String itemId);
  Future<void> write(UnsentSave save);
  Future<void> clear(String itemId);
}

class MemoryUnsentStore implements UnsentStore {
  final Map<String, String> data = {};
  @override
  Future<UnsentSave?> load(String itemId) async {
    final s = data[itemId];
    return s == null ? null : UnsentSave.decode(s);
  }

  @override
  Future<void> write(UnsentSave save) async => data[save.itemId] = save.encode();
  @override
  Future<void> clear(String itemId) async => data.remove(itemId);
}
