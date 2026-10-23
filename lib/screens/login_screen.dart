import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_session.dart';
import '../theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _server = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _key = TextEditingController();
  bool _useKey = false;
  bool _busy = false;
  bool _showPass = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    context.read<AppSession>().lastServer().then((s) {
      if (s != null && mounted && _server.text.isEmpty) _server.text = s;
    });
  }

  @override
  void dispose() {
    _server.dispose();
    _user.dispose();
    _pass.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_server.text.trim().isEmpty) {
      setState(() => _error = 'Enter your server address');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final session = context.read<AppSession>();
    try {
      if (_useKey) {
        await session.loginWithApiKey(_server.text, _key.text);
      } else {
        await session.loginWithPassword(_server.text, _user.text.trim(), _pass.text);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Stack(
        children: [
          // Soft glowing blobs behind the card.
          Positioned(top: -160, left: -120, child: _Glow(color: context.colors.accent.withAlpha(85), size: 520)),
          Positioned(bottom: -200, right: -140, child: _Glow(color: context.colors.secondaryGlow.withAlpha(68), size: 600)),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
              child: const SizedBox(),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(32, 36, 32, 28),
                  decoration: BoxDecoration(
                    color: context.colors.surface.withAlpha(204),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: context.colors.border),
                    boxShadow: const [
                      BoxShadow(color: Color(0x66000000), blurRadius: 40, offset: Offset(0, 20)),
                    ],
                  ),
                  child: AutofillGroup(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _Logo(size: 56),
                        const SizedBox(height: 20),
                        Text('Welcome to Lectern',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Text('Connect to your Audiobookshelf server',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(color: context.colors.muted)),
                        const SizedBox(height: 28),
                        TextField(
                          controller: _server,
                          decoration: const InputDecoration(
                            hintText: 'https://abs.example.com',
                            prefixIcon: Icon(Icons.dns_rounded, size: 20),
                          ),
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 12),
                        AnimatedCrossFade(
                          duration: const Duration(milliseconds: 200),
                          crossFadeState: _useKey ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                          firstChild: Column(
                            children: [
                              TextField(
                                controller: _user,
                                autofillHints: const [AutofillHints.username],
                                decoration: const InputDecoration(
                                  hintText: 'Username',
                                  prefixIcon: Icon(Icons.person_rounded, size: 20),
                                ),
                                textInputAction: TextInputAction.next,
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _pass,
                                obscureText: !_showPass,
                                autofillHints: const [AutofillHints.password],
                                decoration: InputDecoration(
                                  hintText: 'Password',
                                  prefixIcon: const Icon(Icons.lock_rounded, size: 20),
                                  suffixIcon: IconButton(
                                    icon: Icon(_showPass ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                        size: 20),
                                    onPressed: () => setState(() => _showPass = !_showPass),
                                  ),
                                ),
                                onSubmitted: (_) => _submit(),
                              ),
                            ],
                          ),
                          secondChild: TextField(
                            controller: _key,
                            obscureText: true,
                            decoration: const InputDecoration(
                              hintText: 'API key',
                              prefixIcon: Icon(Icons.key_rounded, size: 20),
                            ),
                            onSubmitted: (_) => _submit(),
                          ),
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 200),
                          child: _error == null
                              ? const SizedBox(width: double.infinity)
                              : Padding(
                                  padding: const EdgeInsets.only(top: 14),
                                  child: Text(_error!,
                                      style: theme.textTheme.bodySmall?.copyWith(color: context.colors.danger)),
                                ),
                        ),
                        const SizedBox(height: 22),
                        FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: _busy
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2.5, color: context.colors.onAccent),
                                )
                              : const Text('Sign in'),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: () => setState(() {
                            _useKey = !_useKey;
                            _error = null;
                          }),
                          child: Text(_useKey ? 'Use username & password' : 'Use an API key instead',
                              style: TextStyle(color: context.colors.muted)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );
}

class _Logo extends StatelessWidget {
  const _Logo({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.3),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [context.colors.accentLight, context.colors.accent],
            ),
            boxShadow: [BoxShadow(color: context.colors.accent.withAlpha(85), blurRadius: 24, offset: Offset(0, 8))],
          ),
          child: Icon(Icons.menu_book_rounded, color: context.colors.onAccent, size: size * 0.55),
        ),
      );
}

/// Exposed so the sidebar can reuse the same mark.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 32});
  final double size;

  @override
  Widget build(BuildContext context) => _Logo(size: size);
}
