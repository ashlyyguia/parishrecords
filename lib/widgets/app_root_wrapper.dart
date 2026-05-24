import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/network_connectivity.dart';

/// Paints a light background behind the router and shows offline hint when needed.
class AppRootWrapper extends StatefulWidget {
  final Widget? child;
  const AppRootWrapper({super.key, required this.child});

  @override
  State<AppRootWrapper> createState() => _AppRootWrapperState();
}

class _AppRootWrapperState extends State<AppRootWrapper> {
  static const _scaffoldBg = Color(0xFFF6F7FB);
  bool? _online;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkNetwork() async {
    try {
      final online = await isNetworkOnline();
      if (mounted && _online != online) {
        setState(() => _online = online);
      }
    } catch (_) {
      if (mounted && _online != false) {
        setState(() => _online = false);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pollTimer != null) return;
    _checkNetwork();
    _pollTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      _checkNetwork();
    });
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child ?? const SizedBox.shrink();

    return ColoredBox(
      color: _scaffoldBg,
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          if (_online == false)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Material(
                color: Colors.orange.shade800,
                elevation: 2,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.wifi_off, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'No internet — sign-in and records need a connection.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                        ),
                        TextButton(
                          onPressed: _checkNetwork,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          child: const Text('Retry'),
                        ),
                      ],
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
