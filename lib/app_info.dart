/// Links shown in the About section (Appearance page). A link left empty is
/// hidden.
class AppInfo {
  /// The project's home on GitHub, e.g. 'https://github.com/you/lectern'.
  static const repoUrl = 'https://github.com/majorpaynedof/lectern';

  /// Where people can leave a tip, shown as "Support Lectern" buttons.
  static const tips = <(String label, String url)>[
    ('Tip on Ko-fi', 'https://ko-fi.com/K5N2297O63'),
    ('Buy me a coffee', 'https://buymeacoffee.com/sirloin'),
  ];

  static String get issuesUrl => repoUrl.isEmpty ? '' : '$repoUrl/issues';
}
