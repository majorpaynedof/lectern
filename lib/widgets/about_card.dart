import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_info.dart';
import '../screens/login_screen.dart' show AppLogo;
import '../theme.dart';

/// About Lectern: version, project links, tips and open-source licences.
class AboutCard extends StatelessWidget {
  const AboutCard({super.key});

  @override
  Widget build(BuildContext context) {
    final pal = context.colors;
    final theme = Theme.of(context);

    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snap) {
        final version = snap.data?.version ?? '';
        return Material(
          color: pal.surfaceHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: pal.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const AppLogo(size: 40),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Lectern', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                          Text(
                            [if (version.isNotEmpty) 'Version $version', 'Free and open source (GPL-3.0)']
                                .join('  ·  '),
                            style: TextStyle(color: pal.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'A desktop client for Audiobookshelf. Not affiliated with the Audiobookshelf project. '
                  'Lectern is free; if you enjoy it, a tip helps keep it going.',
                  style: TextStyle(color: pal.textSoft),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final (label, url) in AppInfo.tips)
                      if (url.isNotEmpty)
                        FilledButton.icon(
                          onPressed: () => _open(context, url),
                          icon: const Icon(Icons.favorite_rounded, size: 18),
                          label: Text(label),
                        ),
                    if (AppInfo.repoUrl.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () => _open(context, AppInfo.repoUrl),
                        icon: const Icon(Icons.code_rounded, size: 18),
                        label: const Text('Source code'),
                      ),
                    if (AppInfo.issuesUrl.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () => _open(context, AppInfo.issuesUrl),
                        icon: const Icon(Icons.bug_report_rounded, size: 18),
                        label: const Text('Report a problem'),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => showLicensePage(
                        context: context,
                        applicationName: 'Lectern',
                        applicationVersion: version,
                        applicationIcon: const Padding(
                          padding: EdgeInsets.all(12),
                          child: AppLogo(size: 48),
                        ),
                        applicationLegalese: 'Licensed under the GNU General Public License v3.0.',
                      ),
                      icon: const Icon(Icons.description_outlined, size: 18),
                      label: const Text('Open-source licences'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Future<void> _open(BuildContext context, String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open $url')));
    }
  }
}
