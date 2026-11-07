import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_session.dart';
import '../theme.dart';
import '../title_tools.dart';
import '../util.dart';
import '../widgets/author_avatar.dart';
import '../widgets/cover.dart' show refreshImages;

/// Find all photos, review first: looks each author up online and shows the
/// photo and bio it found. High-confidence matches come ticked; nothing is
/// saved until you accept an author (or "Accept all ticked").
///
/// Returns true if any author was changed.
Future<bool> openAuthorPhotoReview(BuildContext context, List<AuthorSummary> authors) async =>
    await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => AuthorPhotoReviewScreen(authors: authors),
    )) ??
    false;

enum _St { waiting, proposed, nothingNew, notFound, failed, saving, done, skipped }

enum _View { review, high, medium, low, nothingNew, notFound, done }

class _Item {
  _Item(this.author);
  final AuthorSummary author;
  _St status = _St.waiting;
  AuthorLookup? found;
  double score = 0;
  String currentBio = '';
  bool photoChosen = false;
  bool bioChosen = false;
  String? message;

  bool get hasPhoto => (found?.image ?? '').isNotEmpty;

  /// A bio worth offering: found, and not the same as the current one.
  bool get hasBio {
    final b = stripHtml(found?.description ?? '').trim();
    return b.isNotEmpty && titleSimilarity(b, stripHtml(currentBio)) < 0.98;
  }

  int get chosenCount => (hasPhoto && photoChosen ? 1 : 0) + (hasBio && bioChosen ? 1 : 0);

  String get confidence => score >= 0.95 ? 'High' : (score >= 0.8 ? 'Medium' : 'Low');
}

class AuthorPhotoReviewScreen extends StatefulWidget {
  const AuthorPhotoReviewScreen({super.key, required this.authors});
  final List<AuthorSummary> authors;

  @override
  State<AuthorPhotoReviewScreen> createState() => _AuthorPhotoReviewScreenState();
}

class _AuthorPhotoReviewScreenState extends State<AuthorPhotoReviewScreen> {
  late final List<_Item> _items = [for (final a in widget.authors) _Item(a)];
  _View _view = _View.review;
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
          final found = await api.searchAuthor(item.author.name);
          if (found == null) {
            item.status = _St.notFound;
          } else {
            item.found = found;
            item.score = authorSimilarity(item.author.name, found.name);
            if (found.description.trim().isNotEmpty) {
              item.currentBio = (await api.author(item.author.id)).description;
            }
            // Your rule: high confidence comes ticked; anything less waits
            // for you (a photo of the wrong person is easy to get otherwise).
            final high = item.confidence == 'High';
            item.photoChosen = high;
            item.bioChosen = high;
            // Found, but maybe with no photo online and the same bio as yours.
            item.status = (item.hasPhoto || item.hasBio) ? _St.proposed : _St.nothingNew;
          }
          item.message = null;
        } catch (e) {
          item.status = _St.failed;
          item.message = friendlyError(e, service: 'Audible');
        }
        if (mounted) setState(() {});
      }
    }

    // Two at a time: quick, without flooding the server or Audible.
    await Future.wait([worker(), worker()]);
    if (mounted) setState(() => _running = false);
  }

  // ------------------------------------------------------------ actions

  Future<void> _accept(_Item item) async {
    final f = item.found;
    if (f == null || item.chosenCount == 0) return;
    final api = context.read<AppSession>().api!;
    setState(() => item.status = _St.saving);
    final saved = <String>[];
    try {
      if (item.hasPhoto && item.photoChosen) {
        await api.setAuthorImage(item.author.id, f.image);
        saved.add('photo');
      }
      if (item.hasBio && item.bioChosen) {
        await api.updateAuthor(item.author.id, description: f.description, asin: f.asin.isEmpty ? null : f.asin);
        saved.add('bio');
      }
      if (saved.contains('photo')) refreshImages();
      setState(() {
        item.status = _St.done;
        item.message = 'Saved ${saved.join(' and ')}';
        _changed = true;
      });
    } catch (e) {
      setState(() {
        item.status = saved.isEmpty ? _St.proposed : _St.done;
        item.message = saved.isEmpty ? 'Could not save: $e' : 'Saved ${saved.join(' and ')}; the rest failed: $e';
        if (saved.isNotEmpty) _changed = true;
      });
    }
  }

  void _skip(_Item item) => setState(() => item.status = _St.skipped);

  Future<void> _acceptAll(List<_Item> items) async {
    final ready = items.where((i) => i.status == _St.proposed && i.chosenCount > 0).toList();
    if (ready.isEmpty) return;
    final changes = ready.fold<int>(0, (n, i) => n + i.chosenCount);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Save the ticked changes for ${ready.length} authors?'),
        content: Text('$changes changes in total, exactly as ticked on each card.'),
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

  bool _inView(_Item i) {
    final open = i.status == _St.proposed || i.status == _St.saving;
    return switch (_view) {
      _View.review => open,
      _View.high => open && i.confidence == 'High',
      _View.medium => open && i.confidence == 'Medium',
      _View.low => open && i.confidence == 'Low',
      _View.nothingNew => i.status == _St.nothingNew,
      _View.notFound => i.status == _St.notFound || i.status == _St.failed,
      _View.done => i.status == _St.done || i.status == _St.skipped,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.colors;
    int count(bool Function(_Item) f) => _items.where(f).length;
    final checked = count((i) => i.status != _St.waiting);
    bool open(_Item i) => i.status == _St.proposed || i.status == _St.saving;
    final shown = _items.where(_inView).toList();
    final ticked = shown.where((i) => i.status == _St.proposed && i.chosenCount > 0).length;

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
              Row(
                children: [
                  IconButton(
                    onPressed: () {
                      _stop = true;
                      Navigator.of(context).pop(_changed);
                    },
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: 8),
                  Text('Find author photos',
                      style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Looks up authors without a photo. High-confidence matches come ticked. '
                'Nothing is saved until you accept; Skip leaves an author as they are.',
                style: TextStyle(color: pal.muted),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text('Checked $checked of ${_items.length}', style: TextStyle(color: pal.textSoft)),
                  const SizedBox(width: 12),
                  if (_running)
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _stop = true),
                      icon: const Icon(Icons.stop_rounded, size: 18),
                      label: const Text('Stop looking'),
                    )
                  else if (checked < _items.length || _items.any((i) => i.status == _St.failed))
                    OutlinedButton.icon(
                      onPressed: _run,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Look up the rest'),
                    ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: ticked == 0 ? null : () => _acceptAll(shown),
                    icon: const Icon(Icons.done_all_rounded, size: 18),
                    label: Text('Accept all ticked ($ticked)'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_running) LinearProgressIndicator(value: _items.isEmpty ? null : checked / _items.length),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (v, label) in [
                    (_View.review, 'To review (${count(open)})'),
                    (_View.high, 'High (${count((i) => open(i) && i.confidence == 'High')})'),
                    (_View.medium, 'Medium (${count((i) => open(i) && i.confidence == 'Medium')})'),
                    (_View.low, 'Low (${count((i) => open(i) && i.confidence == 'Low')})'),
                    (_View.nothingNew, 'Nothing new (${count((i) => i.status == _St.nothingNew)})'),
                    (_View.notFound, 'Not found (${count((i) => i.status == _St.notFound || i.status == _St.failed)})'),
                    (_View.done, 'Done (${count((i) => i.status == _St.done || i.status == _St.skipped)})'),
                  ])
                    ChoiceChip(label: Text(label), selected: _view == v, onSelected: (_) => setState(() => _view = v)),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: shown.isEmpty
                    ? Center(
                        child: Text(_running ? 'Looking authors up…' : 'Nothing here.',
                            style: TextStyle(color: pal.muted)))
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 40),
                        itemCount: shown.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, n) => _Card(
                          item: shown[n],
                          onChanged: () => setState(() {}),
                          onAccept: () => _accept(shown[n]),
                          onSkip: () => _skip(shown[n]),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.item, required this.onChanged, required this.onAccept, required this.onSkip});
  final _Item item;
  final VoidCallback onChanged;
  final VoidCallback onAccept;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final pal = context.colors;
    final theme = Theme.of(context);
    final f = item.found;
    final open = item.status == _St.proposed;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: pal.surfaceHigh, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.author.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      if (f != null) _Tag('Found: ${f.name}'),
                      if (f != null) _Tag('${item.confidence} confidence', strong: item.confidence == 'High'),
                      if (item.status == _St.notFound) const _Tag('Not found online'),
                      if (item.status == _St.nothingNew)
                        const _Tag('Found, but there\'s no photo online and the bio is the same as yours'),
                    ]),
                  ],
                ),
              ),
              if (open) ...[
                TextButton(onPressed: onSkip, child: const Text('Skip')),
                const SizedBox(width: 6),
                FilledButton(onPressed: item.chosenCount > 0 ? onAccept : null, child: const Text('Accept')),
              ],
              if (item.status == _St.saving)
                const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          if (item.message != null) ...[
            const SizedBox(height: 8),
            Text(item.message!, style: TextStyle(color: item.status == _St.failed ? pal.danger : pal.muted)),
          ],
          if (f != null && item.status != _St.notFound && item.status != _St.nothingNew) ...[
            const SizedBox(height: 14),
            if (item.hasPhoto)
              _Choice(
                label: 'Use this photo',
                chosen: item.photoChosen,
                enabled: open,
                onChanged: (v) {
                  item.photoChosen = v;
                  onChanged();
                },
                child: Row(
                  children: [
                    AuthorAvatar(author: item.author, size: 72),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Icon(Icons.arrow_forward_rounded, color: pal.muted),
                    ),
                    ClipOval(
                      child: SizedBox(
                        width: 72,
                        height: 72,
                        child: Image.network(
                          f.image,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: pal.surface,
                            alignment: Alignment.center,
                            child: Icon(Icons.broken_image_outlined, color: pal.muted),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (item.hasBio) ...[
              const SizedBox(height: 12),
              _Choice(
                label: item.currentBio.trim().isEmpty ? 'Add this bio' : 'Replace the bio',
                chosen: item.bioChosen,
                enabled: open,
                onChanged: (v) {
                  item.bioChosen = v;
                  onChanged();
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (item.currentBio.trim().isNotEmpty) ...[
                      Text('Now: ${stripHtml(item.currentBio)}',
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.muted)),
                      const SizedBox(height: 4),
                    ],
                    Text(stripHtml(f.description), maxLines: 4, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// A tickable change: checkbox, label, and what it would look like.
class _Choice extends StatelessWidget {
  const _Choice(
      {required this.label, required this.chosen, required this.enabled, required this.onChanged, required this.child});
  final String label;
  final bool chosen;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final pal = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(value: chosen, onChanged: enabled ? (v) => onChanged(v ?? false) : null),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 6),
                child: Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: pal.text)),
              ),
              child,
            ],
          ),
        ),
      ],
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
