import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_session.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/cover.dart';

/// Search Audible / Google Books / ... for the right book and copy its
/// details and cover onto this one. Returns true if something was saved.
Future<bool> showMatchBookDialog(BuildContext context, BookDetail book) async =>
    await showDialog<bool>(context: context, builder: (_) => _MatchDialog(book: book)) ?? false;

class _MatchDialog extends StatefulWidget {
  const _MatchDialog({required this.book});
  final BookDetail book;

  @override
  State<_MatchDialog> createState() => _MatchDialogState();
}

class _MatchDialogState extends State<_MatchDialog> {
  late final TextEditingController _title = TextEditingController(text: widget.book.title);
  late final TextEditingController _author = TextEditingController(text: widget.book.author);
  List<MetadataProvider> _providers = MetadataProvider.defaults;
  String _provider = 'audible';
  List<MatchResult>? _results;
  MatchResult? _selected;
  bool _searching = true; // the first search starts right away
  bool _applying = false;
  bool _useCover = true;
  bool _useDetails = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final api = context.read<AppSession>().api!;
    api.bookProviders().then((p) {
      if (!mounted) return;
      setState(() {
        _providers = p;
        if (!p.any((x) => x.value == _provider) && p.isNotEmpty) _provider = p.first.value;
      });
    });
    // setState can't run during initState, so search right after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Enter a title to search for');
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
      _selected = null;
    });
    try {
      final r = await context.read<AppSession>().api!.searchBooks(
            provider: _provider,
            title: _title.text.trim(),
            author: _author.text.trim(),
            itemId: widget.book.id,
          );
      if (mounted) setState(() => _results = r);
    } catch (e) {
      if (mounted) setState(() => _error = 'Search failed: $e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  List<String> _split(String v) => v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  Future<void> _apply() async {
    final r = _selected;
    if (r == null) return;
    final metadata = <String, dynamic>{};
    if (_useDetails) {
      void put(String key, String value) {
        if (value.isNotEmpty) metadata[key] = value;
      }
      put('title', r.title);
      put('subtitle', r.subtitle);
      put('publisher', r.publisher);
      put('publishedYear', r.year);
      put('description', r.description);
      put('asin', r.asin);
      put('isbn', r.isbn);
      if (r.author.isNotEmpty) metadata['authors'] = [for (final n in _split(r.author)) {'name': n}];
      if (r.narrator.isNotEmpty) metadata['narrators'] = _split(r.narrator);
      if (r.genres.isNotEmpty) metadata['genres'] = r.genres;
      if (r.series.isNotEmpty) {
        metadata['series'] = [for (final s in r.series) {'name': s.name, 'sequence': s.sequence ?? ''}];
      }
    }
    final cover = _useCover ? r.coverUrl : null;
    if (metadata.isEmpty && cover == null) return;

    setState(() {
      _applying = true;
      _error = null;
    });
    try {
      await context.read<AppSession>().api!.updateBook(widget.book.id, metadata, coverUrl: cover);
      refreshImages();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _applying = false;
          _error = 'Could not save: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.colors;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 760),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Find a match', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.of(context).pop(false)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 8, 28, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(color: pal.surfaceHigh, borderRadius: BorderRadius.circular(12)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _provider,
                        dropdownColor: pal.surfaceHigh,
                        items: [
                          for (final p in _providers) DropdownMenuItem(value: p.value, child: Text(p.label)),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _provider = v);
                          _search();
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _title,
                      decoration: const InputDecoration(hintText: 'Title', isDense: true),
                      onSubmitted: (_) => _search(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _author,
                      decoration: const InputDecoration(hintText: 'Author', isDense: true),
                      onSubmitted: (_) => _search(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _searching ? null : _search,
                    icon: const Icon(Icons.search_rounded, size: 18),
                    label: const Text('Search'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _searching
                  ? const Center(child: CircularProgressIndicator())
                  : (_results == null || _results!.isEmpty)
                      ? Center(
                          child: Text(
                            _results == null ? '' : 'No results. Try a shorter title or another source.',
                            style: TextStyle(color: pal.muted),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          itemCount: _results!.length,
                          itemBuilder: (_, i) => _ResultTile(
                            result: _results![i],
                            selected: identical(_results![i], _selected),
                            onTap: () => setState(() => _selected = _results![i]),
                          ),
                        ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 4, 28, 0),
                child: Align(alignment: Alignment.centerLeft, child: Text(_error!, style: TextStyle(color: pal.danger))),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 28, 20),
              child: Row(
                children: [
                  Checkbox(value: _useCover, onChanged: (v) => setState(() => _useCover = v ?? true)),
                  const Text('Use this cover'),
                  const SizedBox(width: 16),
                  Checkbox(value: _useDetails, onChanged: (v) => setState(() => _useDetails = v ?? true)),
                  const Text('Use these details'),
                  const Spacer(),
                  TextButton(onPressed: _applying ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: (_selected == null || _applying || (!_useCover && !_useDetails)) ? null : _apply,
                    child: _applying
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: pal.onAccent),
                          )
                        : const Text('Apply'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.result, required this.selected, required this.onTap});
  final MatchResult result;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.colors;
    final r = result;
    final details = [
      if (r.author.isNotEmpty) r.author,
      if (r.narrator.isNotEmpty) 'read by ${r.narrator}',
      if (r.year.isNotEmpty) r.year,
      if (r.durationMinutes > 0) formatDuration(r.durationMinutes * 60, compact: true),
    ].join('  ·  ');
    final series = r.series.map((s) => s.sequence != null && s.sequence!.isNotEmpty ? '${s.name} #${s.sequence}' : s.name).join(', ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: selected ? pal.accentSoft : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? pal.accent : Colors.transparent, width: 1.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 72,
                  height: 72,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: r.coverUrl == null
                        ? const CoverPlaceholder()
                        : Image.network(r.coverUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const CoverPlaceholder()),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.title.isEmpty ? 'Untitled' : r.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      if (series.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(series, style: theme.textTheme.bodySmall?.copyWith(color: pal.accent)),
                        ),
                      if (details.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(details,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(color: pal.muted)),
                        ),
                    ],
                  ),
                ),
                if (selected) Icon(Icons.check_circle_rounded, color: pal.accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
