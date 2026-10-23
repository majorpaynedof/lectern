import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_session.dart';
import '../theme.dart';

/// Round author photo from the server, or their initials if there is none.
class AuthorAvatar extends StatelessWidget {
  const AuthorAvatar({super.key, required this.author, this.size = 120});
  final AuthorSummary author;
  final double size;

  @override
  Widget build(BuildContext context) {
    final api = context.read<AppSession>().api;
    final pal = context.colors;
    final initials = author.name
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
    final fallback = Container(
      color: pal.surfaceHigh,
      alignment: Alignment.center,
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: TextStyle(color: pal.accent, fontSize: size * 0.32, fontWeight: FontWeight.w700),
      ),
    );
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: (api == null || !author.hasImage)
            ? fallback
            : Image.network(
                api.authorImageUri(author.id, width: (size * 2).round()).toString(),
                headers: api.authHeaders,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => fallback,
              ),
      ),
    );
  }
}
