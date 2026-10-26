import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import '../state/app_session.dart';
import '../state/match_finder.dart';
import '../theme.dart';
import '../title_tools.dart';
import '../widgets/cover.dart';

/// Finds a series for books that aren't in one, by looking each book up
/// online. Nothing is changed until you accept a suggestion: every book is
/// Accept, Edit or Skip.
///
/// Returns true if any book was added to a series.
Future<bool> openSeriesFinder(BuildContext context) async =>
    await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const SeriesFinderScreen())) ?? false;

enum _Status { waiting, found, none, failed, saving, accepted }

enum _Filter { suggested, high, medium, low, none }

/// One series a book could join, e.g. "Bobiverse" #3.
class _Option {
  _Option(this.name, this.sequence, {this.existing = false});
  String name;
  String sequence;
  bool existing; // already a series in this library
  bool chosen = true;

  String get label => sequence.isEmpty ? name : '$name #$sequence';
}

class _Item {
  _Item(this.book);
  final BookSummary book;
  _Status status = _Status.waiting;
  PossibleMatch? match;
  List<_Option> options = [];
  String? message; // after accepting, or why it failed

  String get confidence {
    final s = match?.score ?? 0;
    return s >= 0.9 ? 'High' : (s >= 0.75 ? 'Medium' : 'Low');
  }
}

class SeriesFinderScreen extends StatefulWidget {
  const SeriesFinderScreen({super.key});

  @override
  State<SeriesFinderScreen> createState() => _SeriesFinderScreenState();
}

class _SeriesFinderScreenState extends State<SeriesFinderScreen> {
  static const _skippedKey = 'seriesFinderSkipped';

  List<_Item> _items = [];
  List<String> _librarySeries = [];
  Set<String> _skipped = {};
  List<MetadataProvider> _providers = MetadataProvider.defaults;
  String _provider = 'audible';
  _Filter _filter = _Filter.suggested;

  bool _loading = true;
  bool _scanning = false;
  bool _stop = false;
  bool _changed = false;
  int _checked = 0;
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
      final prefs = await SharedPreferences.getInstance();
      _skipped = (prefs.getStringList(_skippedKey) ?? const []).toSet();
      api.bookProviders().then((p) {
        if (mounted) {
          setState(() {
            _providers = p;
            if (!p.any((x) => x.value == _provider) && p.isNotEmpty) _provider = p.first.value;
          });
        }
      });
      final books = await api.allBooks(lib.id);
      final names = <String>[];
      for (var page = 0;; page++) {
        final r = await api.series(lib.id, page: page, limit: 200);
        names.addAll(r.items.map((s) => s.name));
        if (r.raw < 200) break;
      }
      if (!mounted) return;
      setState(() {
        _librarySeries = names;
        _items = [for (final b in books) if (b.series.isEmpty) _Item(b)];
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load the library: $e';
        });
      }
    }
  }

  List<_Item> get _toCheck => [for (final i in _items) if (!_skipped.contains(i.book.id)) i];

  // ------------------------------------------------------------ scanning

  Future<void> _scan() async {
    final api = context.read<AppSession>().api!;
    final queue = [for (final i in _toCheck) if (i.status == _Status.waiting || i.status == _Status.failed) i];
    setState(() {
      _scanning = true;
      _stop = false;
    });

    Future<void> worker() async {
      while (queue.isNotEmpty && !_stop && mounted) {
        final item = queue.removeAt(0);
        try {
          final m = await findSeriesMatch(api,
              provider: _provider, title: item.book.title, author: item.book.author, itemId: item.book.id);
          item.match = m;
          item.options = m == null ? [] : [for (final s in m.result.series) _optionFor(s.name, s.sequence ?? '')];
          item.status = item.options.isEmpty ? _Status.none : _Status.found;
        } catch (e) {
          item.status = _Status.failed;
          item.message = '$e';
        }
        if (mounted) setState(() => _checked++);
      }
    }

    // A couple at a time: quick, without flooding the server.
    await Future.wait([worker(), worker()]);
    if (mounted) setState(() => _scanning = false);
  }

  /// Uses the library's own spelling when the series already exists, so
  /// "Bobiverse" doesn't end up next to "The Bobiverse".
  _Option _optionFor(String name, String sequence) {
    for (final existing in _librarySeries) {
      if (existing.toLowerCase() == name.toLowerCase() || titleSimilarity(existing, name) >= 0.92) {
        return _Option(existing, sequence, existing: true);
      }
    }
    return _Option(name, sequence);
  }

  // ------------------------------------------------------------ actions

  Future<void> _accept(_Item item) async {
    final chosen = item.options.where((o) => o.chosen && o.name.trim().isNotEmpty).toList();
    if (chosen.isEmpty) return;
    setState(() => item.status = _Status.saving);
    try {
      await context.read<AppSession>().api!.updateBook(item.book.id, {
        'series': [for (final o in chosen) {'name': o.name.trim(), 'sequence': o.sequence.trim()}],
      });
      for (final o in chosen) {
        if (!_librarySeries.contains(o.name.trim())) _librarySeries.add(o.name.trim());
      }
      setState(() {
        item.status = _Status.accepted;
        item.message = 'Added to ${chosen.map((o) => o.label).join(', ')}';
        _changed = true;
      });
    } catch (e) {
      setState(() {
        item.status = _Status.found;
        item.message = 'Could not save: $e';
      });
    }
  }

  /// Puts the book back the way it was: in no series.
  Future<void> _undo(_Item item) async {
    setState(() => item.status = _Status.saving);
    try {
      await context.read<AppSession>().api!.updateBook(item.book.id, {'series': <Object>[]});
      setState(() {
        item.status = item.options.isEmpty ? _Status.none : _Status.found;
        item.message = null;
      });
    } catch (e) {
      setState(() {
        item.status = _Status.accepted;
        item.message = 'Could not undo: $e';
      });
    }
  }

  Future<void> _skip(_Item item) async {
    setState(() => _skipped.add(item.book.id));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_skippedKey, _skipped.toList());
  }

  Future<void> _resetSkipped() async {
    setState(() => _skipped.clear());
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_skippedKey);
  }

  Future<void> _edit(_Item item) async {
    final opts = item.options.isEmpty ? [_Option('', '')] : item.options;
    final first = opts.firstWhere((o) => o.chosen, orElse: () => opts.first);
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _EditDialog(
        book: item.book,
        name: first.name,
        sequence: first.sequence,
        librarySeries: _librarySeries,
      ),
    );
    if (result == null || result.$1.trim().isEmpty) return;
    setState(() {
      final o = _optionFor(result.$1.trim(), result.$2.trim());
      item.options = [o];
      if (item.status == _Status.none) item.status = _Status.found;
    });
    await _accept(item);
  }

  Future<void> _acceptAllHigh() async {
    final high = [
      for (final i in _toCheck)
        if (i.status == _Status.found && i.confidence == 'High') i,
    ];
    if (high.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add ${high.length} books to these series?'),
        content: SizedBox(
          width: 520,
          height: 360,
          child: ListView(
            children: [
              for (final i in high)
                ListTile(
                  dense: true,
                  title: Text(i.book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(i.options.where((o) => o.chosen).map((o) => o.label).join(', ')),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add all')),
        ],
      ),
    );
    if (ok != true) return;
    for (final i in high) {
      if (!mounted) return;
      await _accept(i);
    }
  }

  // ------------------------------------------------------------ UI

  List<_Item> _visible() {
    final list = _toCheck;
    bool keep(_Item i) => switch (_filter) {
          _Filter.suggested => i.status == _Status.found || i.status == _Status.saving || i.status == _Status.accepted,
          _Filter.high => i.status != _Status.none && i.match != null && i.confidence == 'High',
          _Filter.medium => i.status != _Status.none && i.match != null && i.confidence == 'Medium',
          _Filter.low => i.status != _Status.none && i.match != null && i.confidence == 'Low',
          _Filter.none => i.status == _Status.none || i.status == _Status.failed,
        };
    return list.where(keep).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.colors;
    final toCheck = _toCheck;
    final total = toCheck.length;
    final found = toCheck.where((i) => i.status == _Status.found).length;
    final highCount = toCheck.where((i) => i.status == _Status.found && i.confidence == 'High').length;
    final accepted = toCheck.where((i) => i.status == _Status.accepted).length;
    final noneCount = toCheck.where((i) => i.status == _Status.none || i.status == _Status.failed).length;
    final waiting = toCheck.where((i) => i.status == _Status.waiting || i.status == _Status.failed).length;
    final checked = toCheck.where((i) => i.status != _Status.waiting).length;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _stop = true;
        Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 40, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () {
                      _stop = true;
                      Navigator.of(context).pop(_changed);
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Find missing series',
                        style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(80, 0, 40, 12),
              child: Text(
                'Looks up books that aren\'t in a series and suggests one. Nothing changes until you choose '
                'Accept or Edit. Skip leaves a book as it is.',
                style: TextStyle(color: pal.muted),
              ),
            ),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Expanded(child: Center(child: Text(_error!, style: TextStyle(color: pal.danger))))
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(80, 0, 40, 12),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(color: pal.surfaceHigh, borderRadius: BorderRadius.circular(12)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _provider,
                          dropdownColor: pal.surfaceHigh,
                          items: [for (final p in _providers) DropdownMenuItem(value: p.value, child: Text(p.label))],
                          onChanged: _scanning ? null : (v) => setState(() => _provider = v ?? _provider),
                        ),
                      ),
                    ),
                    if (_scanning)
                      OutlinedButton.icon(
                        onPressed: () => setState(() => _stop = true),
                        icon: const Icon(Icons.stop_rounded, size: 18),
                        label: Text(_stop ? 'Stopping…' : 'Stop'),
                      )
                    else
                      FilledButton.icon(
                        onPressed: waiting == 0 ? null : _scan,
                        icon: const Icon(Icons.travel_explore_rounded, size: 18),
                        label: Text(_checked == 0 ? 'Look up $total books' : 'Look up remaining $waiting'),
                      ),
                    if (highCount > 0 && !_scanning)
                      OutlinedButton.icon(
                        onPressed: _acceptAllHigh,
                        icon: const Icon(Icons.done_all_rounded, size: 18),
                        label: Text('Review & add all high confidence ($highCount)'),
                      ),
                    if (_skipped.isNotEmpty)
                      TextButton(
                        onPressed: _scanning ? null : _resetSkipped,
                        child: Text('Show ${_skipped.length} skipped again'),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(80, 0, 40, 8),
                child: Text(
                  total == 0
                      ? 'Every book in this library is in a series.'
                      : '$total books without a series  ·  checked $checked  ·  $found suggestions  ·  '
                          '$accepted added  ·  $noneCount with no suggestion',
                  style: theme.textTheme.bodySmall?.copyWith(color: pal.muted),
                ),
              ),
              if (_scanning)
                Padding(
                  padding: const EdgeInsets.fromLTRB(80, 0, 40, 8),
                  child: LinearProgressIndicator(value: total == 0 ? null : checked / total),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(80, 4, 40, 8),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final (f, label) in [
                      (_Filter.suggested, 'Suggestions'),
                      (_Filter.high, 'High'),
                      (_Filter.medium, 'Medium'),
                      (_Filter.low, 'Low'),
                      (_Filter.none, 'No suggestion ($noneCount)'),
                    ])
                      ChoiceChip(
                        label: Text(label),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                  ],
                ),
              ),
              Expanded(child: _buildList(pal)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildList(LecternPalette pal) {
    final items = _visible();
    if (items.isEmpty) {
      final text = _checked == 0
          ? 'Click "Look up" to start. You can stop at any time.'
          : (_scanning ? 'Looking things up…' : 'Nothing here.');
      return Center(child: Text(text, style: TextStyle(color: pal.muted)));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(80, 4, 40, 24),
      itemCount: items.length,
      itemBuilder: (_, i) => _Card(
        item: items[i],
        onAccept: () => _accept(items[i]),
        onEdit: () => _edit(items[i]),
        onSkip: () => _skip(items[i]),
        onUndo: () => _undo(items[i]),
        onToggle: (o) => setState(() => o.chosen = !o.chosen),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.item,
    required this.onAccept,
    required this.onEdit,
    required this.onSkip,
    required this.onUndo,
    required this.onToggle,
  });

  final _Item item;
  final VoidCallback onAccept;
  final VoidCallback onEdit;
  final VoidCallback onSkip;
  final VoidCallback onUndo;
  final ValueChanged<_Option> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.colors;
    final m = item.match;
    final accepted = item.status == _Status.accepted;
    final saving = item.status == _Status.saving;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: pal.surfaceHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: accepted ? pal.accent : pal.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 72, height: 72, child: Cover(itemId: item.book.id, width: 200, radius: 8)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.book.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    Text(item.book.author, style: theme.textTheme.bodySmall?.copyWith(color: pal.muted)),
                    const SizedBox(height: 8),
                    if (accepted)
                      Row(children: [
                        Icon(Icons.check_circle_rounded, size: 18, color: pal.accent),
                        const SizedBox(width: 6),
                        Expanded(child: Text(item.message ?? 'Added', style: TextStyle(color: pal.accent))),
                      ])
                    else if (item.status == _Status.none || item.status == _Status.failed)
                      Text(
                        item.status == _Status.failed
                            ? 'Lookup failed. Try again later.'
                            : 'No series found online. Use Edit to set one yourself, or Skip.',
                        style: TextStyle(color: pal.muted),
                      )
                    else ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          for (final o in item.options)
                            FilterChip(
                              label: Text(o.label),
                              selected: o.chosen,
                              onSelected: saving ? null : (_) => onToggle(o),
                              tooltip: o.existing ? 'Already a series in your library' : 'New series',
                              avatar: Icon(o.existing ? Icons.collections_bookmark_rounded : Icons.add_rounded, size: 16),
                            ),
                          _Tag('${item.confidence} confidence', strong: item.confidence == 'High'),
                        ],
                      ),
                      if (m != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'Matched online: ${m.result.title}${m.result.author.isEmpty ? '' : ' by ${m.result.author}'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(color: pal.muted),
                          ),
                        ),
                      if (item.message != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(item.message!, style: TextStyle(color: pal.danger)),
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (saving)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
                )
              else if (accepted)
                TextButton(onPressed: onUndo, child: const Text('Undo'))
              else
                Wrap(
                  spacing: 8,
                  children: [
                    if (item.status == _Status.found)
                      FilledButton(
                        onPressed: item.options.any((o) => o.chosen) ? onAccept : null,
                        child: const Text('Accept'),
                      ),
                    OutlinedButton(onPressed: onEdit, child: const Text('Edit')),
                    TextButton(onPressed: onSkip, child: const Text('Skip')),
                  ],
                ),
            ],
          ),
        ),
      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: strong ? pal.accentSoft : pal.surface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: TextStyle(fontSize: 12, color: strong ? pal.accent : pal.muted)),
    );
  }
}

/// Set the series name and book number by hand, with names already in the
/// library offered as you type.
class _EditDialog extends StatefulWidget {
  const _EditDialog({required this.book, required this.name, required this.sequence, required this.librarySeries});
  final BookSummary book;
  final String name;
  final String sequence;
  final List<String> librarySeries;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final TextEditingController _sequence = TextEditingController(text: widget.sequence);
  late String _name = widget.name;

  @override
  void dispose() {
    _sequence.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.colors;
    return AlertDialog(
      title: Text(widget.book.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Series', style: TextStyle(color: pal.muted)),
            const SizedBox(height: 6),
            Autocomplete<String>(
              initialValue: TextEditingValue(text: widget.name),
              optionsBuilder: (v) {
                final q = v.text.trim().toLowerCase();
                if (q.isEmpty) return const Iterable<String>.empty();
                return widget.librarySeries.where((s) => s.toLowerCase().contains(q)).take(8);
              },
              onSelected: (s) => _name = s,
              fieldViewBuilder: (context, controller, focus, onSubmit) => TextField(
                controller: controller,
                focusNode: focus,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Series name'),
                onChanged: (v) => _name = v,
              ),
            ),
            const SizedBox(height: 14),
            Text('Book number', style: TextStyle(color: pal.muted)),
            const SizedBox(height: 6),
            TextField(controller: _sequence, decoration: const InputDecoration(hintText: 'e.g. 3 or 2.5')),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, (_name, _sequence.text)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
