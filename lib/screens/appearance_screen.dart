import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/theme_controller.dart';
import '../theme.dart';
import '../widgets/about_card.dart';

/// Lets the user pick one of the built-in color themes.
class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ThemeController>();
    final theme = Theme.of(context);
    final pal = context.colors;

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(40, 40, 40, 40),
        children: [
          Text('Appearance', style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('Choose a color theme. It applies right away and is remembered next time.',
              style: theme.textTheme.bodyLarge?.copyWith(color: pal.muted)),
          const SizedBox(height: 20),
          // A Material (not a decorated Container) so the switch's press
          // effect draws on the card instead of being hidden under it.
          Material(
            color: pal.surfaceHigh,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: pal.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 10, 8),
              child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(Icons.touch_app_rounded, color: pal.accent),
              title: const Text('Touch mode', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                'Bigger buttons, play buttons always shown on covers, and long-press a cover for more options. '
                'For touchscreens; remembered on this computer only.',
                style: TextStyle(color: pal.muted),
              ),
              value: controller.touchMode,
              onChanged: controller.setTouchMode,
            ),
            ),
          ),
          const SizedBox(height: 28),
          for (final group in {for (final p in LecternPalettes.all) p.group}) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(group, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  if (group.endsWith('Inspired'))
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Color schemes inspired by pro team colors. Not affiliated with or endorsed by any league or team.',
                        style: theme.textTheme.bodySmall?.copyWith(color: pal.muted),
                      ),
                    ),
                ],
              ),
            ),
            Wrap(
              spacing: 20,
              runSpacing: 20,
              children: [
                for (final p in LecternPalettes.all.where((p) => p.group == group))
                  _PaletteCard(
                    palette: p,
                    selected: controller.palette.id == p.id,
                    onTap: () => controller.select(p),
                  ),
              ],
            ),
            const SizedBox(height: 28),
          ],
          Text('About', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          const AboutCard(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _PaletteCard extends StatefulWidget {
  const _PaletteCard({required this.palette, required this.selected, required this.onTap});
  final LecternPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_PaletteCard> createState() => _PaletteCardState();
}

class _PaletteCardState extends State<_PaletteCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette; // the palette this card previews
    final current = context.colors; // the palette the app is using now

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 220,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: current.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.selected ? current.accent : (_hover ? current.muted : current.border),
              width: widget.selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MiniPreview(p: p),
              const SizedBox(height: 12),
              Row(
                children: [
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(p.name,
                        style: TextStyle(color: current.text, fontWeight: FontWeight.w600, fontSize: 15)),
                  ),
                  for (final c in [p.bg, p.surfaceHigh, p.accent])
                    Container(
                      width: 14,
                      height: 14,
                      margin: const EdgeInsets.only(left: 4),
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(color: current.border),
                      ),
                    ),
                  const SizedBox(width: 4),
                ],
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  widget.selected ? 'In use' : (p.brightness == Brightness.dark ? 'Dark' : 'Light'),
                  style: TextStyle(color: widget.selected ? current.accent : current.muted, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tiny drawing of the app window in the given palette.
class _MiniPreview extends StatelessWidget {
  const _MiniPreview({required this.p});
  final LecternPalette p;

  @override
  Widget build(BuildContext context) {
    Widget line(double w, Color c, [double h = 6]) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)),
        );

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 124,
        color: p.bg,
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  // sidebar
                  Container(
                    width: 50,
                    color: p.surface,
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(4)),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(color: p.accentSoft, borderRadius: BorderRadius.circular(4)),
                          child: line(26, p.accent, 4),
                        ),
                        const SizedBox(height: 6),
                        Padding(padding: const EdgeInsets.only(left: 3), child: line(22, p.muted, 4)),
                      ],
                    ),
                  ),
                  // content
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          line(70, p.text, 7),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              for (final shade in [0.0, 0.35, 0.6])
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: AspectRatio(
                                      aspectRatio: 1,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Color.lerp(p.surfaceHigh, p.accent, shade),
                                          borderRadius: BorderRadius.circular(5),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // mini player
            Container(
              height: 24,
              color: p.surface,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  line(40, p.textSoft, 4),
                  const Spacer(),
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
                  ),
                  const Spacer(),
                  line(16, p.muted, 4),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
