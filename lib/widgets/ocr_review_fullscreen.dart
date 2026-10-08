import 'package:flutter/material.dart';

/// Shows an OCR review step edge to edge, above the admin/staff shell
/// (no sidebar, no page header), so the wide register table gets the whole
/// window.
///
/// The scan page keeps owning all the state. It passes [refresh] (bumped on
/// every setState) so this route rebuilds whenever the page does, and
/// [builder] builds the same review widgets the page shows inline.
class OcrReviewFullscreen {
  static Future<void> open(
    BuildContext context, {
    required String title,
    required Listenable refresh,
    required WidgetBuilder builder,
  }) {
    return Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (ctx) => Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: Text(title),
            actions: [
              TextButton.icon(
                key: const ValueKey('exit-fullscreen'),
                onPressed: () => Navigator.of(ctx).pop(),
                icon: const Icon(Icons.fullscreen_exit),
                label: const Text('Exit full screen'),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(
            child: AnimatedBuilder(
              animation: refresh,
              builder: (c, _) => builder(c),
            ),
          ),
        ),
      ),
    );
  }
}
