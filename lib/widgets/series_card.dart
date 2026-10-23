import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import 'cover.dart';

/// A series shown as a small fanned stack of its first covers.
class SeriesCard extends StatefulWidget {
  const SeriesCard({super.key, required this.series, required this.onTap});
  final SeriesSummary series;
  final VoidCallback onTap;

  @override
  State<SeriesCard> createState() => _SeriesCardState();
}

class _SeriesCardState extends State<SeriesCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.series;
    final n = s.entries.length;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: AnimatedScale(
                scale: _hover ? 1.035 : 1,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                child: CoverStack(ids: [for (final e in s.entries.take(3)) e.book.id]),
              ),
            ),
            const SizedBox(height: 10),
            Text(s.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('$n ${n == 1 ? 'book' : 'books'}',
                style: theme.textTheme.bodySmall?.copyWith(color: context.colors.muted)),
          ],
        ),
      ),
    );
  }
}

/// Up to three covers fanned out, front one bottom-left.
class CoverStack extends StatelessWidget {
  const CoverStack({super.key, required this.ids, this.radius = 10});
  final List<String> ids;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (ids.isEmpty) return const CoverPlaceholder();
    if (ids.length == 1) return _shadowed(Cover(itemId: ids.first, radius: radius));
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final size = w * (ids.length == 2 ? 0.86 : 0.78);
      final step = (w - size) / (ids.length - 1);
      return Stack(
        children: [
          // Draw back-to-front so the first book ends up on top.
          for (var i = ids.length - 1; i >= 0; i--)
            Positioned(
              left: step * i,
              top: (w - size) - step * i,
              width: size,
              height: size,
              // Back covers are dimmed with a dark overlay rather than an
              // Opacity widget (Opacity over a shadow upsets Flutter's
              // Windows renderer in debug mode).
              child: _shadowed(Stack(
                fit: StackFit.expand,
                children: [
                  Cover(itemId: ids[i], radius: radius, width: 300),
                  if (i > 0)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(i == 1 ? 0x33000000 : 0x59000000),
                        borderRadius: BorderRadius.circular(radius),
                      ),
                    ),
                ],
              )),
            ),
        ],
      );
    });
  }

  Widget _shadowed(Widget child) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 12, offset: Offset(0, 6))],
        ),
        child: child,
      );
}
