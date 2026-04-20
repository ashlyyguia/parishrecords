import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/auth_provider.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _navigated = false;
  String? _error;
  int _dots = 0;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    _animateDots();
    // Set timeout
    _timeoutTimer = Timer(const Duration(seconds: 15), () {
      if (!mounted || _navigated) return;
      setState(
        () => _error =
            'Initialization timed out. Please check your connection and try again.',
      );
    });
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  void _animateDots() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return false;
      setState(() => _dots = (_dots + 1) % 4);
      return mounted;
    });
  }

  void _navigate(AuthState auth) {
    if (_navigated) return;
    if (!auth.initialized) return;

    _navigated = true;
    _timeoutTimer?.cancel();

    if (auth.user == null) {
      context.go('/login');
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final scheme = Theme.of(context).colorScheme;

    // Handle navigation in build - check after first frame
    if (!_navigated && auth.initialized) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _navigate(auth));
    }

    return Scaffold(
      backgroundColor: scheme.surface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(Icons.church, color: scheme.primary, size: 44),
            ),
            const SizedBox(height: 16),
            Text(
              'ParishKeeper',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Loading records${'.' * _dots}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _error != null
                    ? scheme.error
                    : scheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 24),
            if (_error != null) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  setState(() => _error = null);
                  _timeoutTimer?.cancel();
                  _timeoutTimer = Timer(const Duration(seconds: 15), () {
                    if (!mounted || _navigated) return;
                    setState(
                      () => _error =
                          'Initialization timed out. Please check your connection and try again.',
                    );
                  });
                },
                child: const Text('Retry'),
              ),
            ] else ...[
              const SizedBox(
                width: 160,
                child: LinearProgressIndicator(minHeight: 4),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
