import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_session.dart';
import '../theme.dart';
import '../widgets/book_card.dart';
import '../widgets/bulk_progress_dialog.dart';

class _Sort {
  const _Sort(this.label, this.key, this.desc);
  final String label;
  final String key;
  final bool desc;
}

const _sorts = [
  _Sort('Title', 'media.metadata.title', false),
  _Sort('Author', 'media.metadata.authorName', false),
  _Sort('Recently added', 'addedAt', true),
  _Sort('Longest', 'media.duration', true),
];

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.library});
  final Library library;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  static const _pageSize = 60;

  final _scroll = ScrollController();
  final List<BookSummary> _items = [];
  int _page = 0;
  bool _loading = false;
  bool _hasMore = true;
  String? _error;
  _Sort _sort = _sorts.first;

  Timer? _debounce;
  String _query = '';
  List<BookSummary>? _results;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 800) _loadMore();
    });
    _loadMore();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final api = context.read<AppSession>().api!;
      final page = await api.items(widget.library.id,
          page: _page, limit: _pageSize, sort: _sort.key, desc: _sort.desc);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.where((b) => b.hasAudio)); // skip e-book-only items
        _page++;
        _hasMore = page.length == _pageSize;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
      // If a page was mostly e-books, the grid may not fill the window yet,
      // so scrolling can't trigger the next page. Load it straight away.
      if (mounted && _hasMore && _error == null && _items.length < 40) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
      }
    }
  }

  Future<void> _matchAll() async {
    final session = context.read<AppSession>();
    final api = session.api!;
    final options = await showDialog<_MatchAllOptions>(context: context, builder: (_) => const _MatchAllDialog());
    if (options == null || !mounted) return;

    List<BookSummary> books;
    try {
      books = await api.allBooks(widget.library.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load the library: $e')));
      }
      return;
    }
    if (options.onlyMissingCovers) books = books.where((b) => !b.hasCover).toList();
    if (!mounted) return;
    if (books.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nothing to match: every book already has a cover.')));
      return;
    }

    final updated = await runBulk<BookSummary>(
      context,
      title: 'Matching ${books.length} books',
      items: books,
      label: (b) => b.title,
      job: (b) async {
        final r = await api.matchBook(
          b.id,
          provider: options.provider,
          overrideCover: options.replaceExisting,
          overrideDetails: options.replaceExisting,
        );
        return switch (r) {
          'updated' => BulkOutcome.updated,
          'notfound' => BulkOutcome.notFound,
          _ => BulkOutcome.unchanged,
        };
      },
    );
    if (updated > 0 && mounted) _changeSort(_sort); // reload the grid with new covers
  }

  void _changeSort(_Sort s) {
    setState(() {
      _sort = s;
      _items.clear();
      _page = 0;
      _hasMore = true;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _loadMore();
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final query = q.trim();
      _query = query;
      if (query.isEmpty) {
        setState(() => _results = null);
        return;
      }
      try {
        final res = await context.read<AppSession>().api!.search(widget.library.id, query);
        if (mounted && _query == query) setState(() => _results = res);
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final books = _results ?? _items;

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 40, 40, 20),
            child: Row(
              children: [
                Expanded(
                  child: Text('Library',
                      style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
                ),
                SizedBox(
                  width: 280,
                  child: TextField(
                    onChanged: _onSearch,
                    decoration: const InputDecoration(
                      hintText: 'Search titles, authors…',
                      prefixIcon: Icon(Icons.search_rounded, size: 20),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                if (context.read<AppSession>().canEdit) ...[
                  OutlinedButton.icon(
                    onPressed: _matchAll,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.colors.text,
                      side: BorderSide(color: context.colors.border),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                    label: const Text('Match all'),
                  ),
                  const SizedBox(width: 12),
                ],
                PopupMenuButton<_Sort>(
                  tooltip: 'Sort',
                  initialValue: _sort,
                  onSelected: _changeSort,
                  itemBuilder: (_) => [
                    for (final s in _sorts) PopupMenuItem(value: s, child: Text(s.label)),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      color: context.colors.surfaceHigh,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.sort_rounded, size: 18, color: context.colors.muted),
                        const SizedBox(width: 8),
                        Text(_sort.label),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: books.isEmpty && !_loading
                ? Center(
                    child: Text(
                      _error ?? (_results != null ? 'No matches' : 'This library is empty'),
                      style: TextStyle(color: context.colors.muted),
                    ),
                  )
                : Scrollbar(
                    controller: _scroll,
                    child: GridView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(40, 8, 40, 40),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 190,
                        mainAxisSpacing: 28,
                        crossAxisSpacing: 24,
                        childAspectRatio: 0.64,
                      ),
                      itemCount: books.length + (_loading && _results == null ? 1 : 0),
                      itemBuilder: (_, i) => i >= books.length
                          ? const Center(child: CircularProgressIndicator())
                          : BookCard(book: books[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}


class _MatchAllOptions {
  const _MatchAllOptions(this.provider, this.onlyMissingCovers, this.replaceExisting);
  final String provider;
  final bool onlyMissingCovers;
  final bool replaceExisting;
}

class _MatchAllDialog extends StatefulWidget {
  const _MatchAllDialog();

  @override
  State<_MatchAllDialog> createState() => _MatchAllDialogState();
}

class _MatchAllDialogState extends State<_MatchAllDialog> {
  List<MetadataProvider> _providers = MetadataProvider.defaults;
  String _provider = 'audible';
  bool _onlyMissing = true;
  bool _replace = false;

  @override
  void initState() {
    super.initState();
    context.read<AppSession>().api!.bookProviders().then((p) {
      if (mounted) setState(() => _providers = p);
    });
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.colors;
    return AlertDialog(
      title: const Text('Match all books'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Looks up each book online and fills in missing covers and details. '
              'Changes are saved to your server.',
              style: TextStyle(color: pal.textSoft),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                const Text('Search'),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: _providers.any((p) => p.value == _provider) ? _provider : _providers.first.value,
                  dropdownColor: pal.surfaceHigh,
                  items: [for (final p in _providers) DropdownMenuItem(value: p.value, child: Text(p.label))],
                  onChanged: (v) => setState(() => _provider = v ?? _provider),
                ),
              ],
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _onlyMissing,
              onChanged: (v) => setState(() => _onlyMissing = v ?? true),
              title: const Text('Only books without a cover'),
              subtitle: Text('Much faster for a large library', style: TextStyle(color: pal.muted)),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _replace,
              onChanged: (v) => setState(() => _replace = v ?? false),
              title: const Text('Replace existing details and covers'),
              subtitle: Text(
                'Fixes wrong titles and series, but a bad match will overwrite good information.',
                style: TextStyle(color: _replace ? pal.danger : pal.muted),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_MatchAllOptions(_provider, _onlyMissing, _replace)),
          child: const Text('Start'),
        ),
      ],
    );
  }
}
