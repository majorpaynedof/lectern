import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/update_checker.dart';
import '../theme.dart';

/// "Lectern 0.7.2 is available": Download opens the release page; nothing is
/// installed by itself.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final updates = context.watch<UpdateChecker>();
    final r = updates.available;
    if (!updates.showBanner || r == null) return const SizedBox.shrink();
    final pal = context.colors;
    return MaterialBanner(
      backgroundColor: pal.accentSoft,
      leading: Icon(Icons.system_update_alt_rounded, color: pal.accent),
      content: Text('Lectern ${r.version} is available. You have ${updates.currentVersion}.'),
      actions: [
        TextButton(onPressed: updates.skip, child: const Text('Skip this version')),
        TextButton(onPressed: updates.later, child: const Text('Later')),
        FilledButton(
          onPressed: () async {
            final ok = await launchUrl(Uri.parse(r.url), mode: LaunchMode.externalApplication);
            if (!ok && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open ${r.url}')));
            }
          },
          child: const Text('Download'),
        ),
      ],
    );
  }
}

/// The "Check for updates" switch and "Check now" button for the About card.
class UpdateSettings extends StatelessWidget {
  const UpdateSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final updates = context.watch<UpdateChecker>();
    final pal = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Switch(value: updates.enabled, onChanged: updates.setEnabled),
            const SizedBox(width: 8),
            const Expanded(child: Text('Tell me when a new version is out (asks GitHub once a day)')),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: updates.checking ? null : () => updates.check(manual: true),
              icon: updates.checking
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Check now'),
            ),
          ],
        ),
        if (updates.lastResult != null)
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 4),
            child: Text(updates.lastResult!, style: TextStyle(color: pal.muted)),
          ),
      ],
    );
  }
}
