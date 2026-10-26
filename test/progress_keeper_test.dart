// Tests for the rules that keep your place safe. Run with: flutter test
//
// A fake server stands in for Audiobookshelf. `phone(...)` is another device
// saving a position; `down()`/`up()` switch the network off and on.

import 'package:flutter_test/flutter_test.dart';
import 'package:lectern/sync/progress_keeper.dart';

class FakeServer implements ProgressServer {
  double? position;
  int lastUpdate = 0;
  bool reachable = true;

  /// Session ids the server still knows (it forgets them when it restarts).
  final Set<String> sessions = {'s1'};
  final List<String> calls = [];
  double listenedTotal = 0;
  int _nextSession = 2;

  void phone(double pos) {
    position = pos;
    lastUpdate++;
  }

  /// Unreachable until this time on the test clock (network waking up).
  DateTime? downUntil;
  DateTime Function() now = DateTime.now;

  void _net() {
    final until = downUntil;
    if (!reachable || (until != null && now().isBefore(until))) {
      throw Exception('socket is not connected');
    }
  }

  @override
  Future<ServerProgress?> fetch(String itemId) async {
    _net();
    calls.add('fetch');
    final p = position;
    return p == null ? null : ServerProgress(p, lastUpdate);
  }

  @override
  Future<void> sync(String sessionId,
      {required double currentTime, required double listened, required double duration}) async {
    _net();
    if (!sessions.contains(sessionId)) throw ServerRejected('session not found (HTTP 404)');
    calls.add('sync $currentTime');
    position = currentTime;
    listenedTotal += listened;
  }

  @override
  Future<void> close(String sessionId,
      {required double currentTime, required double listened, required double duration}) async {
    _net();
    if (!sessions.contains(sessionId)) throw ServerRejected('session not found (HTTP 404)');
    calls.add('close $currentTime');
    position = currentTime;
    listenedTotal += listened;
    sessions.remove(sessionId);
  }

  @override
  Future<void> put(String itemId, {required double currentTime, required double duration}) async {
    _net();
    calls.add('put $currentTime');
    position = currentTime;
  }

  @override
  Future<String?> renewSession(String itemId) async {
    _net();
    final id = 's${_nextSession++}';
    sessions.add(id);
    calls.add('renew $id');
    return id;
  }

  /// Positions this PC wrote to the server.
  List<String> get writes => calls.where((c) => !c.startsWith('fetch') && !c.startsWith('renew')).toList();
}

class Harness {
  Harness({double start = 18000}) {
    server.position = start;
    server.now = () => clock;
    keeper = ProgressKeeper(
      store: store,
      now: () => clock,
      delay: (d) async => clock = clock.add(d),
      log: logs.add,
    );
  }

  final server = FakeServer();
  final store = MemoryUnsentStore();
  final logs = <String>[];
  DateTime clock = DateTime(2026, 10, 25, 17);
  late ProgressKeeper keeper;

  Future<double> open({String session = 's1'}) => keeper.begin(
        server: server,
        itemId: 'titan',
        sessionId: session,
        duration: 40000,
        serverPosition: server.position ?? 0,
      );

  /// Plays for [seconds] from [from], saving every 15 s like the player.
  Future<double> play(double from, int seconds) async {
    var pos = from;
    for (var i = 0; i < seconds; i++) {
      pos += 1;
      keeper.addListened(1);
      clock = clock.add(const Duration(seconds: 1));
      if ((i + 1) % 15 == 0) await keeper.save(pos, trusted: true);
    }
    return pos;
  }
}

void main() {
  group('normal listening', () {
    test('saves while playing and on pause', () async {
      final h = Harness();
      final start = await h.open();
      expect(start, 18000);
      final pos = await h.play(start, 60);
      expect(await h.keeper.save(pos, trusted: true), SaveResult.sent);
      expect(h.server.position, 18060);
      expect(h.server.listenedTotal, 60);
      expect(h.store.data, isEmpty);
    });

    test('a short pause carries on without checking the server', () async {
      final h = Harness();
      var pos = await h.play(await h.open(), 30);
      await h.keeper.save(pos, trusted: true);
      h.keeper.hold('paused');
      h.keeper.releasePause();
      final fetches = h.server.calls.where((c) => c == 'fetch').length;
      pos = await h.play(pos, 15);
      expect(h.server.position, pos);
      expect(h.server.calls.where((c) => c == 'fetch').length, fetches);
    });
  });

  group('another device', () {
    test('a long pause, then the phone moves on: asks, never overwrites', () async {
      final h = Harness();
      var pos = await h.play(await h.open(), 30);
      await h.keeper.save(pos, trusted: true);
      h.keeper.hold('paused');

      h.server.phone(18420); // listened on the phone meanwhile

      final r = await h.keeper.check(localPosition: pos);
      expect(r, CheckResult.otherDeviceAhead);
      expect(h.keeper.conflict!.currentTime, 18420);

      // Any save before choosing leaves the phone's position alone.
      expect(await h.keeper.save(pos + 15, trusted: true), SaveResult.waitingForChoice);
      expect(h.server.position, 18420);
    });

    test('Jump: carries on from the phone and saves from there', () async {
      final h = Harness();
      var pos = await h.play(await h.open(), 30);
      await h.keeper.save(pos, trusted: true);
      h.keeper.hold('paused');
      h.server.phone(18420);
      await h.keeper.check(localPosition: pos);

      await h.keeper.resolve(jump: true, localPosition: pos);
      expect(h.keeper.conflict, isNull);
      pos = await h.play(18420, 20);
      expect(await h.keeper.save(pos, trusted: true), SaveResult.sent);
      expect(h.server.position, 18440);
    });

    test('Stay here: saves this PC\'s position, even though it\'s behind', () async {
      final h = Harness();
      var pos = await h.play(await h.open(), 30);
      await h.keeper.save(pos, trusted: true);
      h.keeper.hold('paused');
      h.server.phone(18420);
      await h.keeper.check(localPosition: pos);

      await h.keeper.resolve(jump: false, localPosition: pos);
      expect(h.server.position, pos);
      pos = await h.play(pos, 15);
      expect(h.server.position, pos);
    });

    test('phone ended at the same place: no question asked', () async {
      final h = Harness();
      final pos = await h.play(await h.open(), 30);
      await h.keeper.save(pos, trusted: true);
      h.keeper.hold('paused');
      h.server.phone(pos + 4);
      expect(await h.keeper.check(localPosition: pos), CheckResult.clear);
      expect(h.keeper.conflict, isNull);
    });

    test('works even if the PC clock is wrong (no timestamps compared)', () async {
      final h = Harness();
      final pos = await h.play(await h.open(), 30);
      await h.keeper.save(pos, trusted: true);
      h.keeper.hold('paused');
      h.clock = h.clock.add(const Duration(days: 400)); // way off
      h.server.phone(19000);
      h.server.lastUpdate = 0; // and the server's time looks "older"
      expect(await h.keeper.check(localPosition: pos), CheckResult.otherDeviceAhead);
    });
  });

  group('sleep and network', () {
    // Test 5 from the hand tests: this is the bug it found.
    test('PC sleeps while playing, phone moves on, network slow to wake', () async {
      final h = Harness();
      final pos = await h.play(await h.open(), 45);

      // Sleep: the network goes away and the phone plays 5 minutes.
      h.server.reachable = false;
      h.server.phone(pos + 300);
      final phoneSpot = h.server.position;
      h.clock = h.clock.add(const Duration(minutes: 11));

      // Wake: a save from before sleep fails...
      expect(await h.keeper.save(pos + 1, trusted: true), SaveResult.keptOnThisPc);
      // ...the player notices the sleep and holds.
      h.keeper.hold('woke from sleep');

      // The network comes back 6 seconds after waking, during the check.
      h.server.reachable = true;
      h.server.downUntil = h.clock.add(const Duration(seconds: 6));
      expect(await h.keeper.check(localPosition: pos + 1, patient: true), CheckResult.otherDeviceAhead);
      expect(h.logs.any((l) => l.contains('Reached the server after')), isTrue);

      // The phone's place survived. Nothing from this PC replaced it.
      expect(h.server.position, phoneSpot);
      expect(h.store.data, isEmpty, reason: 'the stale position was dropped');
    });

    test('network never comes back: nothing is sent, place kept on this PC', () async {
      final h = Harness();
      var pos = await h.play(await h.open(), 30);
      await h.keeper.save(pos, trusted: true);
      h.server.reachable = false;
      h.keeper.hold('woke from sleep');
      expect(await h.keeper.check(localPosition: pos, patient: true), CheckResult.unreachable);
      expect(h.keeper.problem, ProgressKeeper.problemUnreachable);

      // Listening carries on; saves are kept on this PC, not sent.
      pos = await h.play(pos, 30);
      expect(h.store.data.containsKey('titan'), isTrue);

      // Network back, nobody else listened: the kept place is sent.
      h.server.reachable = true;
      pos = await h.play(pos, 15);
      expect(h.server.position, pos);
      expect(h.keeper.problem, isNull);
      expect(h.store.data, isEmpty);
    });

    test('network back but the phone moved on meanwhile: kept place is dropped', () async {
      final h = Harness();
      var pos = await h.play(await h.open(), 30);
      await h.keeper.save(pos, trusted: true);
      h.server.reachable = false;
      pos = await h.play(pos, 30); // saves fail, kept locally
      h.server.phone(19500);
      h.server.reachable = true;
      expect(await h.keeper.save(pos + 15, trusted: true), SaveResult.waitingForChoice);
      expect(h.server.position, 19500);
    });

    test('a quick pause after "server not reachable" still checks before sending', () async {
      final h = Harness();
      final pos = await h.play(await h.open(), 15);
      h.keeper.hold('paused');
      h.server.reachable = false;
      expect(await h.keeper.check(localPosition: pos), CheckResult.unreachable);
      h.keeper.releasePause(); // a 2-second pause and play
      expect(h.keeper.gateOpen, isFalse);
    });

    test('a dropped save is retried only after checking the server', () async {
      final h = Harness();
      var pos = await h.play(await h.open(), 15);
      h.server.reachable = false;
      expect(await h.keeper.save(pos + 1, trusted: true), SaveResult.keptOnThisPc);
      expect(h.keeper.gateOpen, isFalse);
      h.server.reachable = true;
      h.server.calls.clear();
      await h.keeper.save(pos + 16, trusted: true);
      expect(h.server.calls.first, 'fetch');
      expect(h.server.position, pos + 16);
    });

    test('three failed saves show a warning, which clears when saving works', () async {
      final h = Harness();
      final pos = await h.play(await h.open(), 15);
      h.server.reachable = false;
      for (var i = 1; i <= 3; i++) {
        await h.keeper.save(pos + i * 15, trusted: true);
      }
      expect(h.keeper.problem, isNotNull);
      h.server.reachable = true;
      await h.keeper.save(pos + 60, trusted: true);
      expect(h.keeper.problem, isNull);
      expect(h.server.position, pos + 60);
    });
  });

  group('player not sure where it is', () {
    test('no audio device / failed load: 0:00 is never saved', () async {
      final h = Harness();
      await h.open();
      expect(await h.keeper.save(0, trusted: false), SaveResult.untrusted);
      await h.keeper.close(0, trusted: false);
      expect(h.server.position, 18000);
      expect(h.server.writes.every((w) => !w.contains(' 0.0')), isTrue);
    });

    test('a big backwards move nobody asked for is refused', () async {
      final h = Harness();
      final pos = await h.play(await h.open(), 30);
      await h.keeper.save(pos, trusted: true);
      expect(await h.keeper.save(120, trusted: true), SaveResult.blockedBackwards);
      expect(h.server.position, pos);
      expect(h.keeper.problem, ProgressKeeper.problemBackwards);
    });

    test('going back yourself is fine', () async {
      final h = Harness();
      final pos = await h.play(await h.open(), 30);
      await h.keeper.save(pos, trusted: true);
      h.keeper.userSeeked(600); // picked an earlier chapter
      expect(await h.keeper.save(615, trusted: true), SaveResult.sent);
      expect(h.server.position, 615);
    });

    test('small skips back (30 s button) are always fine', () async {
      final h = Harness();
      final pos = await h.play(await h.open(), 60);
      await h.keeper.save(pos, trusted: true);
      expect(await h.keeper.save(pos - 25, trusted: true), SaveResult.sent);
    });
  });

  group('closing and reopening', () {
    test('close saves the final position and ends the session', () async {
      final h = Harness();
      final pos = await h.play(await h.open(), 20);
      await h.keeper.close(pos, trusted: true);
      expect(h.server.calls.last, 'close $pos');
      expect(h.keeper.active, isFalse);
    });

    test('close after a long pause when the phone moved on keeps the phone\'s place', () async {
      final h = Harness();
      final pos = await h.play(await h.open(), 30);
      await h.keeper.save(pos, trusted: true);
      h.keeper.hold('paused');
      h.server.phone(20000);
      await h.keeper.close(pos, trusted: true);
      expect(h.server.position, 20000);
    });

    test('closed while offline: next time carries on from this PC\'s place', () async {
      final h = Harness();
      var pos = await h.play(await h.open(), 30);
      await h.keeper.save(pos, trusted: true);
      h.server.reachable = false;
      pos = await h.play(pos, 120);
      await h.keeper.close(pos, trusted: true);
      expect(h.store.data.containsKey('titan'), isTrue);

      // Next launch, server reachable, nobody else listened.
      h.server.reachable = true;
      h.server.sessions.add('s9');
      final start = await h.open(session: 's9');
      expect(start, pos);
      expect(h.server.position, pos);
      expect(h.store.data, isEmpty);
    });

    test('closed while offline, then another app saved an OLDER spot: offered, not used', () async {
      final h = Harness();
      var pos = await h.play(await h.open(), 60);
      await h.keeper.save(pos, trusted: true); // 18060 saved
      h.server.reachable = false;
      pos = await h.play(pos, 120); // 18180 kept on this PC
      await h.keeper.close(pos, trusted: true);

      h.server.reachable = true;
      h.server.phone(18030); // another app writes back an older position
      h.server.sessions.add('s9');
      expect(await h.open(session: 's9'), 18030, reason: 'starts at the server\'s spot');
      expect(h.keeper.offlineSpot, pos, reason: 'but offers the later one');
      expect(h.server.position, 18030, reason: 'nothing sent until you choose');

      // Choosing it is just going there; the next save sends it.
      h.keeper.offlineSpot = null;
      h.keeper.userSeeked(pos);
      expect(await h.keeper.save(pos + 15, trusted: true), SaveResult.sent);
      expect(h.server.position, pos + 15);
    });

    test('closed while offline, then the phone moved on: the phone wins', () async {
      final h = Harness();
      var pos = await h.play(await h.open(), 30);
      await h.keeper.save(pos, trusted: true);
      h.server.reachable = false;
      pos = await h.play(pos, 120);
      await h.keeper.close(pos, trusted: true);

      h.server.reachable = true;
      h.server.phone(25000);
      h.server.sessions.add('s9');
      expect(await h.open(session: 's9'), 25000);
      expect(h.keeper.offlineSpot, isNull, reason: 'the phone is further on: no question');
      expect(h.server.position, 25000);
      expect(h.store.data, isEmpty);
    });
  });

  group('server restarted', () {
    test('forgotten session: saves directly and starts a new session', () async {
      final h = Harness();
      final pos = await h.play(await h.open(), 15);
      h.server.sessions.clear(); // server restarted
      expect(await h.keeper.save(pos + 15, trusted: true), SaveResult.sent);
      expect(h.server.position, pos + 15);
      expect(h.keeper.sessionId, 's2');
      await h.keeper.save(pos + 30, trusted: true);
      expect(h.server.calls.last, 'sync ${pos + 30}');
    });
  });
}
