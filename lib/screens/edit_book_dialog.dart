import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_session.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/cover.dart';

/// Opens the "Edit details" form. Returns true if something was saved.
Future<bool> showEditBookDialog(BuildContext context, BookDetail book) async =>
    await showDialog<bool>(context: context, builder: (_) => _EditBookDialog(book: book)) ?? false;

class _SeriesRow {
  _SeriesRow(String name, String sequence)
      : name = TextEditingController(text: name),
        sequence = TextEditingController(text: sequence);
  final TextEditingController name;
  final TextEditingController sequence;
  void dispose() {
    name.dispose();
    sequence.dispose();
  }
}

class _EditBookDialog extends StatefulWidget {
  const _EditBookDialog({required this.book});
  final BookDetail book;

  @override
  State<_EditBookDialog> createState() => _EditBookDialogState();
}

class _EditBookDialogState extends State<_EditBookDialog> {
  late final TextEditingController _title, _subtitle, _authors, _narrators, _year, _publisher, _genres, _description, _cover;
  late final String _originalDescription;
  final List<_SeriesRow> _series = [];
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final b = widget.book;
    _title = TextEditingController(text: b.title);
    _subtitle = TextEditingController(text: b.subtitle);
    _authors = TextEditingController(
        text: b.authorRefs.isNotEmpty ? b.authorRefs.map((a) => a.name).join(', ') : b.author);
    _narrators = TextEditingController(text: b.narrators.join(', '));
    _year = TextEditingController(text: b.year ?? '');
    _publisher = TextEditingController(text: b.publisher);
    _genres = TextEditingController(text: b.genres.join(', '));
    _originalDescription = stripHtml(b.description);
    _description = TextEditingController(text: _originalDescription);
    _cover = TextEditingController();
    for (final r in b.seriesRefs) {
      _series.add(_SeriesRow(r.name, r.sequence ?? ''));
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _subtitle, _authors, _narrators, _year, _publisher, _genres, _description, _cover]) {
      c.dispose();
    }
    for (final r in _series) {
      r.dispose();
    }
    super.dispose();
  }

  List<String> _split(String v) => v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Enter a title');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final metadata = <String, dynamic>{
      'title': _title.text.trim(),
      'subtitle': _subtitle.text.trim(),
      'authors': [for (final n in _split(_authors.text)) {'name': n}],
      'narrators': _split(_narrators.text),
      'series': [
        for (final r in _series)
          if (r.name.text.trim().isNotEmpty) {'name': r.name.text.trim(), 'sequence': r.sequence.text.trim()},
      ],
      'publishedYear': _year.text.trim(),
      'publisher': _publisher.text.trim(),
      'genres': _split(_genres.text),
      // Only send the description if it changed, so formatting the server
      // keeps (which we don't show here) isn't lost.
      if (_description.text.trim() != _originalDescription) 'description': _description.text.trim(),
    };
    try {
      await context.read<AppSession>().api!.updateBook(widget.book.id, metadata, coverUrl: _cover.text.trim());
      refreshImages();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = context.colors;

    Widget field(String label, TextEditingController c, {int maxLines = 1, String? hint}) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelMedium?.copyWith(color: pal.muted)),
              const SizedBox(height: 6),
              TextField(controller: c, maxLines: maxLines, minLines: 1, decoration: InputDecoration(hintText: hint)),
            ],
          ),
        );

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 780),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Edit details', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.of(context).pop(false)),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 8, 28, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    field('Title', _title),
                    field('Subtitle', _subtitle),
                    field('Authors', _authors, hint: 'Separate several with commas'),
                    field('Narrators', _narrators, hint: 'Separate several with commas'),
                    Text('Series', style: theme.textTheme.labelMedium?.copyWith(color: pal.muted)),
                    const SizedBox(height: 6),
                    for (final r in _series)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(child: TextField(controller: r.name, decoration: const InputDecoration(hintText: 'Series name'))),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 90,
                              child: TextField(controller: r.sequence, decoration: const InputDecoration(hintText: 'Book #')),
                            ),
                            IconButton(
                              tooltip: 'Remove',
                              icon: Icon(Icons.remove_circle_outline_rounded, color: pal.muted),
                              onPressed: () => setState(() {
                                _series.remove(r);
                                r.dispose();
                              }),
                            ),
                          ],
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add series'),
                        onPressed: () => setState(() => _series.add(_SeriesRow('', ''))),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: field('Year', _year)),
                        const SizedBox(width: 12),
                        Expanded(flex: 2, child: field('Publisher', _publisher)),
                      ],
                    ),
                    field('Genres', _genres, hint: 'Separate several with commas'),
                    field('Description', _description, maxLines: 8),
                    field('New cover from a web address (optional)', _cover, hint: 'https://…/cover.jpg'),
                  ],
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 4, 28, 0),
                child: Text(_error!, style: TextStyle(color: pal.danger)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 12, 28, 22),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: pal.onAccent),
                          )
                        : const Text('Save'),
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
