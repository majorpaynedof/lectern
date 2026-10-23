import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_session.dart';
import '../theme.dart';
import '../widgets/author_avatar.dart';
import '../widgets/bulk_progress_dialog.dart';
import 'author_screen.dart';

/// Every author in the library, with a quick name filter.
class AuthorsScreen extends StatefulWidget {
  const AuthorsScreen({super.key, required this.library});
  final Library library;

  @override
  State<AuthorsScreen> createState() => _AuthorsScreenState();
}

class _AuthorsScreenState extends State<AuthorsScreen> {
  late Future<List<AuthorSummary>> _future;
  String _query = '';
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _future = context.read<AppSession>().api!.authors(widget.library.id);
  }

  Future<void> _findAllPhotos() async {
    final api = context.read<AppSession>().api!;
    final List<AuthorSummary> all;
    try {
      all = await _future;
    } catch (_) {
      return;
    }
    final missing = all.where((a) => !a.hasImage).toList();
    if (!mounted) return;
    if (missing.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Every author already has a photo.')));
      return;
    }
    final updated = await runBulk<AuthorSummary>(
      context,
      title: 'Finding photos for ${missing.length} authors',
      items: missing,
      label: (a) => a.name,
      job: (a) async => await api.matchAuthor(a.id, a.name) ? BulkOutcome.updated : BulkOutcome.notFound,
    );
    if (updated > 0 && mounted) {
      setState(() {
        _future = api.authors(widget.library.id);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.colors;

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 40, 40, 20),
            child: Row(
              children: [
                Expanded(
                  child: Text('Authors', style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
                ),
                if (context.read<AppSession>().canEdit) ...[
                  OutlinedButton.icon(
                    onPressed: _findAllPhotos,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.colors.text,
                      side: BorderSide(color: context.colors.border),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                    label: const Text('Find all photos'),
                  ),
                  const SizedBox(width: 12),
                ],
                SizedBox(
                  width: 280,
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                    decoration: const InputDecoration(
                      hintText: 'Find an author…',
                      prefixIcon: Icon(Icons.search_rounded, size: 20),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<AuthorSummary>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Text('Could not load authors.\n${snap.error}',
                        textAlign: TextAlign.center, style: TextStyle(color: pal.muted)),
                  );
                }
                final authors = _query.isEmpty
                    ? snap.data!
                    : snap.data!.where((a) => a.name.toLowerCase().contains(_query)).toList();
                if (authors.isEmpty) {
                  return Center(child: Text('No authors found', style: TextStyle(color: pal.muted)));
                }
                return Scrollbar(
                  controller: _scroll,
                  child: GridView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(40, 8, 40, 40),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 170,
                      mainAxisSpacing: 26,
                      crossAxisSpacing: 20,
                      childAspectRatio: 0.74,
                    ),
                    itemCount: authors.length,
                    itemBuilder: (_, i) => _AuthorTile(author: authors[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthorTile extends StatefulWidget {
  const _AuthorTile({required this.author});
  final AuthorSummary author;

  @override
  State<_AuthorTile> createState() => _AuthorTileState();
}

class _AuthorTileState extends State<_AuthorTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = widget.author;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AuthorScreen(authorId: a.id, name: a.name),
        )),
        child: LayoutBuilder(builder: (context, c) {
          final size = c.maxWidth * 0.86;
          return Column(
            children: [
              AnimatedScale(
                scale: _hover ? 1.05 : 1,
                duration: const Duration(milliseconds: 180),
                child: AuthorAvatar(author: a, size: size),
              ),
              const SizedBox(height: 12),
              Text(a.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text('${a.numBooks} ${a.numBooks == 1 ? 'book' : 'books'}',
                  style: theme.textTheme.bodySmall?.copyWith(color: context.colors.muted)),
            ],
          );
        }),
      ),
    );
  }
}
