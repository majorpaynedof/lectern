import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_session.dart';
import '../state/match_finder.dart';
import '../theme.dart';
import '../title_tools.dart';
import '../util.dart';
import '../widgets/cover.dart';
import 'match_book_dialog.dart';

/// Match all, review first: looks every book up online and shows what would
/// change. Nothing is saved until you accept a book (or "Accept all").
///
/// Returns true if any book was changed.
Future<bool> openMatchReview(
  BuildContext context, {
  required List<BookSummary> books,
  required String provider,
  required bool suggestReplacing,
}) async =>
    await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => MatchReviewScreen(books: books, provider: provider, suggestReplacing: suggestReplacing),
    )) ??
    false;

enum _St { waiting, proposed, notFound, upToDate, failed, saving, done, skipped }

enum _View { proposed, notFound, upToDate, done }

/// One detail that would change, e.g. Title: "All These Worlds: Bobiverse,
/// Book 3" -> "All These Worlds".
class _Field {
  _Field(this.label, this.current, this.proposed, this.value, {required this.chosen});
  final String label;
  final String current;
  final String proposed;
  final Object value; // what gets saved
  bool chosen;
  bool get fills => current.trim().isEmpty;
}

class _Item {
  _Item(this.book);
  final BookSummary book;
  _St status = _St.waiting;
  BookDetail? detail;
  MatchResult? match;
  double score = 0;
  String how = '';
  Map<String, _Field> fields = {};
  String? coverUrl;
  bool coverChosen = false;
  List<PossibleMatch> possible = [];
  String? message;

  int get chosenCount => fields.values.where((f) => f.chosen).length + (coverUrl != null && coverChosen ? 1 : 0);
  String get confidence => score >= 0.9 ? 'High' : (score >= 0.75 ? 'Medium' : 'Low');
}

class MatchReviewScreen extends StatefulWidget {
  const MatchReviewScreen({super.key, required this.books, required this.provider, required this.suggestReplacing});
  final List<BookSummary> books;
  final String provider;

  /// Also pre-tick changes to details that are already filled in (normally
  /// only empty details and missing covers are pre-ticked).
  final bool suggestReplacing;

  @override
  State<MatchReviewScreen> createState() => _MatchReviewScreenState();
}

class _MatchReviewScreenState extends State<MatchReviewScreen> {
  late final List<_Item> _items = [for (final b in widget.books) _Item(b)];
  _View _view = _View.proposed;
  bool _running = false;
  bool _stop = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
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
          item.detail = await api.item(item.book.id);
          final results = await api.searchBooks(
              provider: widget.provider, title: item.book.title, author: item.book.author, itemId: item.book.id);
          final best = _best(item.book, results);
          if (best != null) {
            _propose(item, best.$1, best.$2, 'Found by title');
          } else {
            item.possible = await findPossibleMatches(api,
                provider: widget.provider, title: item.book.title, author: item.book.author, itemId: item.book.id);
            item.status = _St.notFound;
          }
        } catch (e) {
          item.status = _St.failed;
          item.message = '$e';
        }
        if (mounted) setState(() {});
      }
    }

    await Future.wait([worker(), worker()]);
    if (mounted) setState(() => _running = false);
  }

  /// The search result that is clearly this book, if any.
  (MatchResult, double)? _best(BookSummary book, List<MatchResult> results) {
    (MatchResult, double)? best;
    for (final r in results) {
      final t = titleSimilarity(book.title, r.title);
      final a = book.author.trim().isEmpty ? 1.0 : authorSimilarity(book.author, r.author);
      if (t < 0.6 || a < 0.5) continue;
      final score = 0.7 * t + 0.3 * a;
      if (best == null || score > best.$2) best = (r, score);
    }
    return best;
  }

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  static List<String> _split(String v) => v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  /// Works out which details would change if this result were used.
  void _propose(_Item item, MatchResult r, double score, String how) {
    final d = item.detail!;
    final fields = <String, _Field>{};
    void add(String key, String label, String current, String proposed, Object value, {bool compareLoosely = false}) {
      if (proposed.trim().isEmpty) return;
      final same = compareLoosely
          ? titleSimilarity(current, proposed) >= 0.98
          : _norm(current) == _norm(proposed);
      if (same) return;
      fields[key] = _Field(label, current, proposed, value,
          chosen: current.trim().isEmpty || widget.suggestReplacing);
    }

    String seriesLabel(Iterable<SeriesRef> s) =>
        s.map((x) => (x.sequence ?? '').isEmpty ? x.name : '${x.name} #${x.sequence}').join(', ');

    add('title', 'Title', d.title, r.title, r.title);
    add('subtitle', 'Subtitle', d.subtitle, r.subtitle, r.subtitle);
    add('authors', 'Author', d.author, r.author, [for (final n in _split(r.author)) {'name': n}]);
    add('narrators', 'Narrator', d.narrators.join(', '), r.narrator, _split(r.narrator));
    add('series', 'Series', seriesLabel(d.seriesRefs), seriesLabel(r.series),
        [for (final s in r.series) {'name': s.name, 'sequence': s.sequence ?? ''}]);
    add('publishedYear', 'Year', d.year ?? '', r.year, r.year);
    add('publisher', 'Publisher', d.publisher, r.publisher, r.publisher);
    add('genres', 'Genres', d.genres.join(', '), r.genres.join(', '), r.genres);
    add('description', 'Description', stripHtml(d.description), stripHtml(r.description), r.description,
        compareLoosely: true);

    item
      ..match = r
      ..score = score
      ..how = how
      ..fields = fields
      ..coverUrl = (r.coverUrl != null && r.coverUrl!.isNotEmpty) ? r.coverUrl : null
      ..coverChosen = !item.book.hasCover || widget.suggestReplacing
      ..message = null;
    final anything = fields.isNotEmpty || item.coverUrl != null;
    item.status = anything ? _St.proposed : _St.upToDate;
  }

  // ------------------------------------------------------------ actions

  Future<void> _accept(_Item item) async {
    final metadata = <String, dynamic>{
      for (final e in item.fields.entries)
        if (e.value.chosen) e.key: e.value.value,
    };
    final cover = item.coverChosen ? item.coverUrl : null;
    if (metadata.isEmpty && cover == null) return;
    setState(() => item.status = _St.saving);
    try {
      await context.read<AppSession>().api!.updateBook(item.book.id, metadata, coverUrl: cover);
      if (cover != null) refreshImages();
      setState(() {
        item.status = _St.done;
        item.message = 'Saved ${item.chosenCount} change${item.chosenCount == 1 ? '' : 's'}';
        _changed = true;
      });
    } catch (e) {
      setState(() {
        item.status = _St.proposed;
        item.message = 'Could not save: $e';
      });
    }
  }

  void _skip(_Item item) => setState(() => item.status = _St.skipped);

  /// Turns one of the "possible matches" into a proposal to review.
  void _usePossible(_Item item, PossibleMatch p) {
    setState(() {
      _propose(item, p.result, p.score, p.reason);
      if (item.status == _St.upToDate) item.message = 'That match is the same as what you have.';
    });
  }

  /// Opens the normal Match window for one book (search by hand).
  Future<void> _searchByHand(_Item item) async {
    final d = item.detail;
    if (d == null) return;
    if (await showMatchBookDialog(context, d)) {
      setState(() {
        item.status = _St.done;
        item.message = 'Matched by hand';
        _changed = true;
      });
    }
  }

  Future<void> _acceptAll(List<_Item> items) async {
    final ready = items.where((i) => i.status == _St.proposed && i.chosenCount > 0).toList();
    if (ready.isEmpty) return;
    final changes = ready.fold<int>(0, (n, i) => n + i.chosenCount);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Save the ticked changes for ${ready.length} books?'),
        content: Text('$changes changes in total, exactly as ticked on each card. This can\'t be undone.'),
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

  // ------------------------------------------------------------ UI

  bool _inView(_Item i) => switch (_view) {
        _View.proposed => i.status == _St.proposed || i.status == _St.saving,
        _View.notFound => i.status == _St.notFound || i.status == _St.failed,
        _View.upToDate => i.status == _St.upToDate,
        _View.done => i.status == _St.done || i.status == _St.skipped,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.colors;
    int count(bool Function(_Item) f) => _items.where(f).length;
    final checked = count((i) => i.status != _St.waiting);
    final proposed = count((i) => i.status == _St.proposed || i.status == _St.saving);
    final notFound = count((i) => i.status == _St.notFound || i.status == _St.failed);
    final upToDate = count((i) => i.status == _St.upToDate);
    final done = count((i) => i.status == _St.done || i.status == _St.skipped);
    final waiting = count((i) => i.status == _St.waiting || i.status == _St.failed);
    final visible = _items.where(_inView).toList();

    void leave() {
      _stop = true;
      Navigator.of(context).pop(_changed);
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) leave();
      },
      child: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 40, 4),
              child: Row(children: [
                IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back_rounded), onPressed: leave),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Review matches',
                      style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(80, 0, 40, 10),
              child: Text(
                'Nothing is saved until you accept. Untick any change you don\'t want, or Skip a book to leave it as it is.',
                style: TextStyle(color: pal.muted),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(80, 0, 40, 8),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Checked $checked of ${_items.length}', style: TextStyle(color: pal.textSoft)),
                  if (_running)
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _stop = true),
                      icon: const Icon(Icons.stop_rounded, size: 18),
                      label: Text(_stop ? 'Stopping…' : 'Stop looking up'),
                    )
                  else if (waiting > 0)
                    OutlinedButton.icon(
                      onPressed: _run,
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: Text('Look up remaining $waiting'),
                    ),
                  if (_view == _View.proposed && proposed > 0)
                    FilledButton.icon(
                      onPressed: () => _acceptAll(visible),
                      icon: const Icon(Icons.done_all_rounded, size: 18),
                      label: Text('Accept all $proposed shown'),
                    ),
                ],
              ),
            ),
            if (_running)
              Padding(
                padding: const EdgeInsets.fromLTRB(80, 0, 40, 6),
                child: LinearProgressIndicator(value: _items.isEmpty ? null : checked / _items.length),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(80, 6, 40, 8),
              child: Wrap(spacing: 8, children: [
                for (final (v, label) in [
                  (_View.proposed, 'Changes to review ($proposed)'),
                  (_View.notFound, 'Not found ($notFound)'),
                  (_View.upToDate, 'Already up to date ($upToDate)'),
                  (_View.done, 'Done or skipped ($done)'),
                ])
                  ChoiceChip(label: Text(label), selected: _view == v, onSelected: (_) => setState(() => _view = v)),
              ]),
            ),
            Expanded(
              child: visible.isEmpty
                  ? Center(
                      child: Text(_running ? 'Looking books up…' : 'Nothing here.', style: TextStyle(color: pal.muted)))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(80, 4, 40, 24),
                      itemCount: visible.length,
                      itemBuilder: (_, i) {
                        final item = visible[i];
                        return switch (item.status) {
                          _St.notFound || _St.failed => _NotFoundCard(
                              item: item,
                              onUse: (p) => _usePossible(item, p),
                              onSearch: () => _searchByHand(item),
                              onSkip: () => _skip(item),
                            ),
                          _ => _ProposalCard(
                              item: item,
                              onAccept: () => _accept(item),
                              onSkip: () => _skip(item),
                              onSearch: () => _searchByHand(item),
                              onChanged: () => setState(() {}),
                            ),
                        };
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProposalCard extends StatelessWidget {
  const _ProposalCard({
    required this.item,
    required this.onAccept,
    required this.onSkip,
    required this.onSearch,
    required this.onChanged,
  });
  final _Item item;
  final VoidCallback onAccept;
  final VoidCallback onSkip;
  final VoidCallback onSearch;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.colors;
    final m = item.match;
    final editable = item.status == _St.proposed;

    return _CardFrame(
      highlight: item.status == _St.done,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BookHeader(
            item: item,
            trailing: [
              if (m != null) _Tag('${item.confidence} confidence', strong: item.confidence == 'High'),
              if (item.how.isNotEmpty && item.how != 'Found by title') _Tag(item.how),
            ],
          ),
          if (m != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 88),
              child: Text(
                'Matched online: ${m.title}${m.author.isEmpty ? '' : ' by ${m.author}'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: pal.muted),
              ),
            ),
          if (item.status == _St.done || item.status == _St.skipped || item.status == _St.upToDate)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 88),
              child: Text(
                item.status == _St.skipped
                    ? 'Skipped. Nothing changed.'
                    : (item.message ?? (item.status == _St.upToDate ? 'Already matches. Nothing to change.' : 'Saved')),
                style: TextStyle(color: item.status == _St.done ? pal.accent : pal.muted),
              ),
            )
          else ...[
            const SizedBox(height: 10),
            if (item.coverUrl != null)
              _CoverRow(item: item, enabled: editable, onChanged: onChanged),
            for (final f in item.fields.values)
              _FieldRow(field: f, enabled: editable, onChanged: onChanged),
            if (item.message != null)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 88),
                child: Text(item.message!, style: TextStyle(color: pal.danger)),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                const SizedBox(width: 88),
                if (item.status == _St.saving)
                  const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                else ...[
                  FilledButton(
                    onPressed: item.chosenCount > 0 ? onAccept : null,
                    child: Text(item.chosenCount == 0
                        ? 'Nothing ticked'
                        : 'Accept ${item.chosenCount} change${item.chosenCount == 1 ? '' : 's'}'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: onSearch, child: const Text('Search by hand…')),
                  const SizedBox(width: 8),
                  TextButton(onPressed: onSkip, child: const Text('Skip')),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _NotFoundCard extends StatelessWidget {
  const _NotFoundCard({required this.item, required this.onUse, required this.onSearch, required this.onSkip});
  final _Item item;
  final ValueChanged<PossibleMatch> onUse;
  final VoidCallback onSearch;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.colors;
    return _CardFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BookHeader(item: item),
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 88),
            child: Text(
              item.status == _St.failed
                  ? 'Lookup failed. Try "Look up remaining" again later.'
                  : (item.possible.isEmpty
                      ? 'No match found, even with a cleaned-up title and author.'
                      : 'No exact match. Possible matches. Choose Review to see what would change:'),
              style: TextStyle(color: pal.muted),
            ),
          ),
          for (final p in item.possible.take(4))
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 88),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          [p.result.title, if (p.result.author.isNotEmpty) p.result.author].join('  ·  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Wrap(spacing: 6, runSpacing: 4, children: [
                          if (p.result.series.isNotEmpty)
                            _Tag(p.result.series
                                .map((s) => (s.sequence ?? '').isEmpty ? s.name : '${s.name} #${s.sequence}')
                                .join(', ')),
                          _Tag(p.closeness, strong: p.score >= 0.8),
                          _Tag(p.reason),
                        ]),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: () => onUse(p), child: const Text('Review')),
                ],
              ),
            ),
          const SizedBox(height: 10),
          Row(children: [
            const SizedBox(width: 88),
            OutlinedButton(onPressed: onSearch, child: const Text('Search by hand…')),
            const SizedBox(width: 8),
            TextButton(onPressed: onSkip, child: const Text('Skip')),
          ]),
        ],
      ),
    );
  }
}

class _BookHeader extends StatelessWidget {
  const _BookHeader({required this.item, this.trailing = const []});
  final _Item item;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.colors;
    return Row(
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
              if (trailing.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(spacing: 6, runSpacing: 4, children: trailing),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Current value -> proposed value, with a tick box.
class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.field, required this.enabled, required this.onChanged});
  final _Field field;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final pal = context.colors;
    final long = field.label == 'Description';
    String short(String s) => long && s.length > 140 ? '${s.substring(0, 140)}…' : s;

    return Padding(
      padding: const EdgeInsets.only(left: 76, top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: field.chosen,
            onChanged: enabled
                ? (v) {
                    field.chosen = v ?? false;
                    onChanged();
                  }
                : null,
          ),
          SizedBox(
            width: 92,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(field.label, style: TextStyle(color: pal.muted, fontSize: 13)),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text.rich(
                TextSpan(children: [
                  if (field.fills)
                    TextSpan(text: 'empty  →  ', style: TextStyle(color: pal.muted, fontStyle: FontStyle.italic))
                  else ...[
                    TextSpan(
                      text: short(field.current),
                      style: TextStyle(
                        color: pal.muted,
                        decoration: field.chosen ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    TextSpan(text: '  →  ', style: TextStyle(color: pal.muted)),
                  ],
                  TextSpan(
                    text: short(field.proposed),
                    style: TextStyle(color: field.chosen ? pal.text : pal.muted, fontWeight: FontWeight.w600),
                  ),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverRow extends StatelessWidget {
  const _CoverRow({required this.item, required this.enabled, required this.onChanged});
  final _Item item;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final pal = context.colors;
    return Padding(
      padding: const EdgeInsets.only(left: 76, top: 2, bottom: 4),
      child: Row(
        children: [
          Checkbox(
            value: item.coverChosen,
            onChanged: enabled
                ? (v) {
                    item.coverChosen = v ?? false;
                    onChanged();
                  }
                : null,
          ),
          SizedBox(width: 92, child: Text('Cover', style: TextStyle(color: pal.muted, fontSize: 13))),
          if (item.book.hasCover) ...[
            SizedBox(width: 56, height: 56, child: Cover(itemId: item.book.id, width: 120, radius: 6)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text('→', style: TextStyle(color: pal.muted)),
            ),
          ] else
            Text('none  →  ', style: TextStyle(color: pal.muted, fontStyle: FontStyle.italic)),
          SizedBox(
            width: 56,
            height: 56,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(item.coverUrl!,
                  fit: BoxFit.cover, errorBuilder: (_, __, ___) => const CoverPlaceholder()),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardFrame extends StatelessWidget {
  const _CardFrame({required this.child, this.highlight = false});
  final Widget child;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final pal = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: pal.surfaceHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: highlight ? pal.accent : pal.border),
        ),
        child: Padding(padding: const EdgeInsets.all(14), child: child),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: strong ? pal.accentSoft : pal.surface, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(fontSize: 12, color: strong ? pal.accent : pal.muted)),
    );
  }
}
