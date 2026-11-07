import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../series_check.dart';
import '../state/app_session.dart';
import '../state/match_finder.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/cover.dart';

/// Check series, review first: for books already in a series, looks each one
/// up online and offers a missing or different book number. Also lists two
/// books with the same number in one series. High-confidence fixes come
/// ticked; nothing changes until you accept.
///
/// Returns true if any book was changed.
Future<bool> openCheckSeries(BuildContext context) async =>
    await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const CheckSeriesScreen())) ?? false;

enum _St { waiting, fixes, fine, notFound, failed, saving, done, skipped }

enum _View { review, duplicates, fine, notFound, done }

class _Fix {
  _Fix(this.fix, this.chosen);
  final SeriesFix fix;
  bool chosen;
}

class _Item {
  _Item(this.book, this.places);
  final BookSummary book;
  final List<SeriesPlace> places;
  _St status = _St.waiting;
  double score = 0;
  List<_Fix> fixes = [];
  String? message;

  String get confidence => score >= 0.9 ? 'High' : (score >= 0.75 ? 'Medium' : 'Low');
  bool get anyChosen => fixes.any((f) => f.chosen);
}

class CheckSeriesScreen extends StatefulWidget {
  const CheckSeriesScreen({super.key});

  @override
  State<CheckSeriesScreen> createState() => _CheckSeriesScreenState();
}

class _CheckSeriesScreenState extends State<CheckSeriesScreen> {
  List<_Item> _items = [];
  Map<String, Map<String, List<String>>> _dupes = {};
  List<MetadataProvider> _providers = MetadataProvider.defaults;
  String _provider = 'audible';
  _View _view = _View.review;
  bool _loading = true;
  bool _running = false;
  bool _stop = false;
  bool _changed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = context.read<AppSession>();
    final api = session.api!;
    final lib = session.currentLibrary;
    if (lib == null) {
      setState(() {
        _loading = false;
        _error = 'No library selected';
      });
      return;
    }
    try {
      api.bookProviders().then((p) {
        if (mounted && p.isNotEmpty) {
          setState(() {
            _providers = p;
            if (!p.any((x) => x.value == _provider)) _provider = p.first.value;
          });
        }
      });
      final books = await api.allBooks(lib.id);
      if (!mounted) return;
      setState(() {
        _items = [
          for (final b in books)
            if (b.series.trim().isNotEmpty) _Item(b, parseSeries(b.series)),
        ];
        _dupes = findDuplicateNumbers({for (final i in _items) i.book.id: i.places});
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load the library: ${friendlyError(e)}';
        });
      }
    }
  }

  // ------------------------------------------------------------ looking up

  Future<void> _run() async {
    final api = context.read<AppSession>().api!;
    final queue = [for (final i in _items) if (i.status == _St.waiting || i.status == _St.failed) i];
    setState(() {
      _running = true;
      _stop = false;
    });

    Future<void> worker() async {
      while (queue.isNotEmpty && !_stop && mounted) {
        final item = queue.removeAt(0);
        try {
          final m = await findSeriesMatch(api,
              provider: _provider, title: item.book.title, author: item.book.author, itemId: item.book.id);
          if (m == null) {
            item.status = _St.notFound;
          } else {
            item.score = m.score;
            final found = [for (final s in m.result.series) (name: s.name, sequence: s.sequence ?? '')];
            final high = item.confidence == 'High';
            item.fixes = [for (final f in checkBookSeries(item.places, found)) _Fix(f, high)];
            item.status = item.fixes.isEmpty ? _St.fine : _St.fixes;
          }
          item.message = null;
        } catch (e) {
          item.status = _St.failed;
          item.message = friendlyError(e, service: MetadataProvider.labelOf(_provider, _providers));
        }
        if (mounted) setState(() {});
      }
    }

    await Future.wait([worker(), worker()]);
    if (mounted) setState(() => _running = false);
  }

  // ------------------------------------------------------------ saving

  /// Sets new numbers on a book, keeping every other series it's in as it
  /// is. [numbers] maps series name (any case) to the new number.
  Future<void> _setNumbers(String bookId, Map<String, String> numbers) async {
    final api = context.read<AppSession>().api!;
    final detail = await api.item(bookId);
    final want = {for (final e in numbers.entries) e.key.trim().toLowerCase(): e.value.trim()};
    await api.updateBook(bookId, {
      'series': [
        for (final r in detail.seriesRefs)
          {'name': r.name, 'sequence': want[r.name.trim().toLowerCase()] ?? (r.sequence ?? '')},
      ],
    });
  }

  Future<void> _accept(_Item item) async {
    final chosen = item.fixes.where((f) => f.chosen).map((f) => f.fix).toList();
    if (chosen.isEmpty) return;
    setState(() => item.status = _St.saving);
    try {
      await _setNumbers(item.book.id, {for (final f in chosen) f.series: f.to});
      setState(() {
        item.status = _St.done;
        item.message = 'Saved: ${chosen.map((f) => f.describe).join('; ')}';
        _changed = true;
      });
    } catch (e) {
      setState(() {
        item.status = _St.fixes;
        item.message = 'Could not save: ${friendlyError(e)}';
      });
    }
  }

  Future<void> _acceptAll() async {
    final ready = _items.where((i) => i.status == _St.fixes && i.anyChosen).toList();
    if (ready.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Change the series numbers of ${ready.length} books?'),
        content: const Text('Exactly as ticked on each card.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save all')),
        ],
      ),
    );
    if (ok != true) return;
    for (final i in ready) {
      if (!mounted) return;
      await _accept(i);
    }
  }

  /// Change one book's number in one series by hand (for duplicates).
  Future<void> _editNumber(_Item item, String series, String current) async {
    final ctrl = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Number in $series'),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(helperText: item.book.title),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Save')),
        ],
      ),
    );
    if (result == null || sameSequence(result, current)) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _setNumbers(item.book.id, {series: result});
      setState(() {
        final i = item.places.indexWhere((p) => p.name.toLowerCase() == series.toLowerCase());
        if (i >= 0) item.places[i] = (name: item.places[i].name, sequence: result.trim());
        _dupes = findDuplicateNumbers({for (final x in _items) x.book.id: x.places});
        _changed = true;
      });
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not save: ${friendlyError(e)}')));
    }
  }

  // ------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.colors;
    int count(_St s) => _items.where((i) => i.status == s).length;
    final checked = _items.where((i) => i.status != _St.waiting).length;
    final open = _items.where((i) => i.status == _St.fixes || i.status == _St.saving).toList();
    final ticked = open.where((i) => i.status == _St.fixes && i.anyChosen).length;
    final dupeCount = _dupes.values.fold<int>(0, (n, m) => n + m.length);

    final List<_Item> shown = switch (_view) {
      _View.review => open,
      _View.fine => _items.where((i) => i.status == _St.fine).toList(),
      _View.notFound => _items.where((i) => i.status == _St.notFound || i.status == _St.failed).toList(),
      _View.done => _items.where((i) => i.status == _St.done || i.status == _St.skipped).toList(),
      _View.duplicates => const [],
    };

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _stop = true;
          Navigator.of(context).pop(_changed);
        }
      },
      child: Scaffold(
        body: Padding(
          padding: const EdgeInsets.fromLTRB(40, 32, 40, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                IconButton(
                  onPressed: () {
                    _stop = true;
                    Navigator.of(context).pop(_changed);
                  },
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const SizedBox(width: 8),
                Text('Check series', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 6),
              Text(
                'For books already in a series: looks each up and offers a missing or different book number, '
                'and lists books sharing a number. High-confidence fixes come ticked; nothing changes until you accept.',
                style: TextStyle(color: pal.muted),
              ),
              const SizedBox(height: 14),
              if (_loading)
                const Expanded(child: Center(child: CircularProgressIndicator()))
              else if (_error != null)
                Expanded(child: Center(child: Text(_error!, style: TextStyle(color: pal.danger))))
              else ...[
                Row(children: [
                  DropdownButton<String>(
                    value: _provider,
                    onChanged: _running ? null : (v) => setState(() => _provider = v ?? _provider),
                    items: [for (final p in _providers) DropdownMenuItem(value: p.value, child: Text(p.label))],
                  ),
                  const SizedBox(width: 12),
                  if (_running)
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _stop = true),
                      icon: const Icon(Icons.stop_rounded, size: 18),
                      label: const Text('Stop looking'),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: checked < _items.length || count(_St.failed) > 0 ? _run : null,
                      icon: const Icon(Icons.search_rounded, size: 18),
                      label: Text(checked == 0 ? 'Look up ${_items.length} books' : 'Look up remaining'),
                    ),
                  const SizedBox(width: 12),
                  Text('Checked $checked of ${_items.length}', style: TextStyle(color: pal.textSoft)),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: ticked == 0 ? null : _acceptAll,
                    icon: const Icon(Icons.done_all_rounded, size: 18),
                    label: Text('Accept all ticked ($ticked)'),
                  ),
                ]),
                const SizedBox(height: 10),
                if (_running) LinearProgressIndicator(value: _items.isEmpty ? null : checked / _items.length),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final (v, label) in [
                    (_View.review, 'To review (${open.length})'),
                    (_View.duplicates, 'Same number twice ($dupeCount)'),
                    (_View.fine, 'Looks right (${count(_St.fine)})'),
                    (_View.notFound, 'Not found (${count(_St.notFound) + count(_St.failed)})'),
                    (_View.done, 'Done (${count(_St.done) + count(_St.skipped)})'),
                  ])
                    ChoiceChip(label: Text(label), selected: _view == v, onSelected: (_) => setState(() => _view = v)),
                ]),
                const SizedBox(height: 14),
                Expanded(
                  child: _view == _View.duplicates
                      ? _duplicatesList()
                      : shown.isEmpty
                          ? Center(
                              child: Text(
                                checked == 0 && !_running && _view == _View.review
                                    ? 'Press "Look up" to check ${_items.length} books. '
                                        'Books sharing a number are already listed under "Same number twice".'
                                    : (_running ? 'Looking books up…' : 'Nothing here.'),
                                textAlign: TextAlign.center,
                                style: TextStyle(color: pal.muted),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.only(bottom: 40),
                              itemCount: shown.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (_, n) => _card(shown[n]),
                            ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(_Item item) {
    final pal = context.colors;
    final open = item.status == _St.fixes;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: pal.surfaceHigh, borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 56, height: 56, child: Cover(itemId: item.book.id, width: 200, radius: 8)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.book.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('${item.book.author} · ${item.book.series}', style: TextStyle(color: pal.muted, fontSize: 13)),
                if (item.status != _St.waiting && item.status != _St.notFound && item.status != _St.failed)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _Tag('${item.confidence} confidence', strong: item.confidence == 'High'),
                  ),
                for (final f in item.fixes)
                  Row(children: [
                    Checkbox(value: f.chosen, onChanged: open ? (v) => setState(() => f.chosen = v ?? false) : null),
                    Text(f.fix.describe),
                  ]),
                if (item.message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(item.message!,
                        style: TextStyle(color: item.status == _St.failed ? pal.danger : pal.muted)),
                  ),
              ],
            ),
          ),
          if (open) ...[
            TextButton(onPressed: () => setState(() => item.status = _St.skipped), child: const Text('Skip')),
            const SizedBox(width: 6),
            FilledButton(onPressed: item.anyChosen ? () => _accept(item) : null, child: const Text('Accept')),
          ],
          if (item.status == _St.saving)
            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
        ],
      ),
    );
  }

  Widget _duplicatesList() {
    final pal = context.colors;
    if (_dupes.isEmpty) {
      return Center(child: Text('No two books share a number in the same series.', style: TextStyle(color: pal.muted)));
    }
    final byId = {for (final i in _items) i.book.id: i};
    final groups = <(String, String, List<_Item>)>[
      for (final s in _dupes.entries)
        for (final n in s.value.entries) (s.key, n.key, [for (final id in n.value) if (byId[id] != null) byId[id]!]),
    ];
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 40),
      itemCount: groups.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, n) {
        final (series, number, books) = groups[n];
        final shownNumber = number.endsWith('.0') ? number.substring(0, number.length - 2) : number;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: pal.surfaceHigh, borderRadius: BorderRadius.circular(14)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$series #$shownNumber', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              Text('${books.length} books have this number. Sometimes that\'s right (two editions); '
                  'otherwise change one.', style: TextStyle(color: pal.muted)),
              const SizedBox(height: 8),
              for (final b in books)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    SizedBox(width: 40, height: 40, child: Cover(itemId: b.book.id, width: 120, radius: 6)),
                    const SizedBox(width: 12),
                    Expanded(child: Text('${b.book.title} · ${b.book.author}', overflow: TextOverflow.ellipsis)),
                    TextButton(
                      onPressed: () {
                        final place = b.places.firstWhere(
                          (p) => p.name.toLowerCase() == series.toLowerCase(),
                          orElse: () => (name: series, sequence: shownNumber),
                        );
                        _editNumber(b, place.name, place.sequence);
                      },
                      child: const Text('Change number'),
                    ),
                  ]),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.strong = false});
  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final pal = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: strong ? pal.accentSoft : pal.surface, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(fontSize: 12, color: strong ? pal.accent : pal.muted)),
    );
  }
}
