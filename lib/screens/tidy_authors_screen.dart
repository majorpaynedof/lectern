import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../author_tidy.dart';
import '../models.dart';
import '../state/app_session.dart';
import '../theme.dart';

/// Tidy author names, review first: finds authors whose name is really a
/// folder name or "Last, First" and suggests the plain name. Renaming to an
/// author you already have merges them. Nothing changes until you accept.
///
/// Returns true if any author was changed.
Future<bool> openTidyAuthors(BuildContext context, List<AuthorSummary> authors) async =>
    await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => TidyAuthorsScreen(authors: authors),
    )) ??
    false;

enum _St { proposed, saving, done, skipped }

class _Item {
  _Item(this.author, this.tidy) : name = tidy.name, chosen = tidy.confidence == 'High';
  final AuthorSummary author;
  AuthorTidy tidy;
  String name; // what it will be renamed to (editable)
  bool chosen;
  _St status = _St.proposed;
  String? message;
}

class TidyAuthorsScreen extends StatefulWidget {
  const TidyAuthorsScreen({super.key, required this.authors});
  final List<AuthorSummary> authors;

  @override
  State<TidyAuthorsScreen> createState() => _TidyAuthorsScreenState();
}

class _TidyAuthorsScreenState extends State<TidyAuthorsScreen> {
  late final Set<String> _names = {for (final a in widget.authors) a.name};
  late final Map<String, int> _books = {for (final a in widget.authors) a.name: a.numBooks};
  late final List<_Item> _items = [
    for (final a in widget.authors)
      if (suggestAuthorName(a.name, _names) ?? suggestDuplicate(a.name, _books) case final t?) _Item(a, t),
  ];
  bool _changed = false;
  bool _showDone = false;

  /// After a rename, a name that didn't exist may exist now (two folder-name
  /// authors both becoming "Tom Clancy"): show the merge on the rest.
  void _refreshMerges() {
    for (final i in _items.where((i) => i.status == _St.proposed)) {
      final t = suggestAuthorName(i.author.name, _names) ?? suggestDuplicate(i.author.name, _books);
      if (t != null && i.name == i.tidy.name) {
        i.tidy = t;
        i.name = t.name;
      }
    }
  }

  String? _mergeTarget(_Item i) {
    final key = i.name.trim().toLowerCase();
    for (final n in _names) {
      if (n != i.author.name && n.toLowerCase() == key) return n;
    }
    return null;
  }

  Future<void> _accept(_Item item) async {
    final newName = _mergeTarget(item) ?? item.name.trim();
    if (newName.isEmpty || newName == item.author.name) return;
    final merging = _names.contains(newName);
    setState(() => item.status = _St.saving);
    try {
      await context.read<AppSession>().api!.updateAuthor(item.author.id, name: newName);
      setState(() {
        item.status = _St.done;
        final books = item.author.numBooks;
        item.message = merging
            ? 'Merged into $newName ($books book${books == 1 ? '' : 's'} moved)'
            : 'Renamed to $newName';
        _names
          ..remove(item.author.name)
          ..add(newName);
        _books.remove(item.author.name);
        _books[newName] = (_books[newName] ?? 0) + books;
        _changed = true;
        _refreshMerges();
      });
    } catch (e) {
      setState(() {
        item.status = _St.proposed;
        item.message = 'Could not save: $e';
      });
    }
  }

  Future<void> _acceptAll() async {
    final ready = _items.where((i) => i.status == _St.proposed && i.chosen).toList();
    if (ready.isEmpty) return;
    final merges = ready.where((i) => _mergeTarget(i) != null).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Rename ${ready.length} authors?'),
        content: Text(
          '$merges of them will merge into an author you already have; their books move there '
          'and the old entry is removed. This can\'t be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Rename all')),
        ],
      ),
    );
    if (ok != true) return;
    for (final i in ready) {
      if (!mounted) return;
      if (i.status == _St.proposed) await _accept(i);
    }
  }

  Future<void> _edit(_Item item) async {
    final ctrl = TextEditingController(text: item.name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename to'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(helperText: 'Was: ${item.author.name}'),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('OK')),
        ],
      ),
    );
    if (result == null || result.trim().isEmpty) return;
    setState(() {
      item.name = result.trim();
      item.chosen = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.colors;
    final open = _items.where((i) => i.status == _St.proposed || i.status == _St.saving).toList();
    final done = _items.where((i) => i.status == _St.done || i.status == _St.skipped).toList();
    final shown = _showDone ? done : open;
    final ticked = open.where((i) => i.status == _St.proposed && i.chosen).length;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
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
                    onPressed: () => Navigator.of(context).pop(_changed),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: 8),
                  Text('Tidy author names', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Authors whose name is really a folder name or "Last, First", or the same person listed twice. '
                'Renaming to an author you '
                'already have merges them: the books move there and the old entry is removed. '
                'Merges come ticked; nothing changes until you accept.',
                style: TextStyle(color: pal.muted),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  ChoiceChip(
                    label: Text('To review (${open.length})'),
                    selected: !_showDone,
                    onSelected: (_) => setState(() => _showDone = false),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text('Done (${done.length})'),
                    selected: _showDone,
                    onSelected: (_) => setState(() => _showDone = true),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: ticked == 0 ? null : _acceptAll,
                    icon: const Icon(Icons.done_all_rounded, size: 18),
                    label: Text('Accept all ticked ($ticked)'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: shown.isEmpty
                    ? Center(
                        child: Text(
                          _items.isEmpty ? 'All author names look fine.' : 'Nothing here.',
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
          ),
        ),
      ),
    );
  }

  Widget _card(_Item item) {
    final pal = context.colors;
    final open = item.status == _St.proposed;
    final target = _mergeTarget(item);
    final books = item.author.numBooks;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 12),
      decoration: BoxDecoration(color: pal.surfaceHigh, borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: item.chosen,
            onChanged: open ? (v) => setState(() => item.chosen = v ?? false) : null,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.author.name, style: TextStyle(color: pal.muted, decoration: TextDecoration.lineThrough)),
                  const SizedBox(height: 2),
                  Text('→ ${target ?? item.name}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    _Tag(item.tidy.reason),
                    _Tag('$books book${books == 1 ? '' : 's'}'),
                    if (target != null)
                      _Tag('Merges with $target (${_books[target] ?? 0} books)', strong: true)
                    else
                      const _Tag('New name'),
                  ]),
                  if (item.message != null) ...[
                    const SizedBox(height: 6),
                    Text(item.message!, style: TextStyle(color: pal.muted)),
                  ],
                ],
              ),
            ),
          ),
          if (open) ...[
            TextButton(onPressed: () => _edit(item), child: const Text('Edit')),
            TextButton(onPressed: () => setState(() => item.status = _St.skipped), child: const Text('Skip')),
            const SizedBox(width: 6),
            FilledButton(onPressed: item.chosen ? () => _accept(item) : null, child: const Text('Accept')),
          ],
          if (item.status == _St.saving)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
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
