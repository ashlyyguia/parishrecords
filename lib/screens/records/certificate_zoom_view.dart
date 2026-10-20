import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A certificate page fitted to the available space, with pinch / wheel /
/// double-tap zoom, panning, and a floating toolbar:
/// zoom out, zoom level (tap to fit), zoom in, fit to screen, full screen.
class CertificateZoomView extends StatefulWidget {
  const CertificateZoomView({
    super.key,
    required this.aspectRatio,
    required this.pageBuilder,
    this.onFullscreen,
    this.fullscreen = false,
  });

  /// Page width / height.
  final double aspectRatio;
  final WidgetBuilder pageBuilder;

  /// Enter full screen (or, when [fullscreen] is true, leave it).
  final VoidCallback? onFullscreen;
  final bool fullscreen;

  static const double minScale = 0.5;
  static const double maxScale = 5;
  static const double step = 1.25;

  @override
  State<CertificateZoomView> createState() => _CertificateZoomViewState();
}

class _CertificateZoomViewState extends State<CertificateZoomView> {
  final _controller = TransformationController();
  Size _viewport = Size.zero;
  double _scale = 1;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTransform);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTransform);
    _controller.dispose();
    super.dispose();
  }

  void _onTransform() {
    final s = _controller.value.getMaxScaleOnAxis();
    if ((s - _scale).abs() > 0.001) setState(() => _scale = s);
  }

  /// Zooms to [target] keeping the scene point under [focal] (viewport
  /// coordinates, default the centre) where it is.
  void _zoomTo(double target, {Offset? focal}) {
    final s = target.clamp(CertificateZoomView.minScale, CertificateZoomView.maxScale);
    final f = focal ?? _viewport.center(Offset.zero);
    final scene = _controller.toScene(f);
    _controller.value = Matrix4.diagonal3Values(s, s, 1)
      ..setTranslationRaw(f.dx - scene.dx * s, f.dy - scene.dy * s, 0);
  }

  void _zoomIn() => _zoomTo(_scale * CertificateZoomView.step);
  void _zoomOut() => _zoomTo(_scale / CertificateZoomView.step);
  void _fit() => _controller.value = Matrix4.identity();

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.equal, control: true): _zoomIn,
        const SingleActivator(LogicalKeyboardKey.add, control: true): _zoomIn,
        const SingleActivator(LogicalKeyboardKey.numpadAdd, control: true): _zoomIn,
        const SingleActivator(LogicalKeyboardKey.minus, control: true): _zoomOut,
        const SingleActivator(LogicalKeyboardKey.numpadSubtract, control: true): _zoomOut,
        const SingleActivator(LogicalKeyboardKey.digit0, control: true): _fit,
      },
      child: Focus(
        autofocus: !widget.fullscreen,
        child: LayoutBuilder(
          builder: (context, box) {
            _viewport = Size(box.maxWidth, box.maxHeight);
            const margin = 20.0;
            final availW = (box.maxWidth - margin * 2).clamp(1.0, double.infinity);
            final availH = (box.maxHeight - margin * 2 - 56).clamp(1.0, double.infinity);
            var pageW = availW;
            var pageH = pageW / widget.aspectRatio;
            if (pageH > availH) {
              pageH = availH;
              pageW = pageH * widget.aspectRatio;
            }
            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onDoubleTapDown: (d) => _scale > 1.05
                        ? _fit()
                        : _zoomTo(2, focal: d.localPosition),
                    onDoubleTap: () {},
                    child: InteractiveViewer(
                      transformationController: _controller,
                      minScale: CertificateZoomView.minScale,
                      maxScale: CertificateZoomView.maxScale,
                      boundaryMargin: EdgeInsets.all(box.maxWidth),
                      child: SizedBox(
                        width: box.maxWidth,
                        height: box.maxHeight,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 56),
                          child: Center(
                            child: Container(
                              width: pageW,
                              height: pageH,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: widget.fullscreen ? 0.4 : 0.1),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: widget.pageBuilder(context),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 12,
                  child: Center(child: _toolbar(context)),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _toolbar(BuildContext context) {
    final dark = widget.fullscreen;
    final fg = dark ? Colors.white : const Color(0xFF1F2937);
    Widget btn(IconData icon, String tip, VoidCallback? onTap) => IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tip,
      color: fg,
      disabledColor: fg.withValues(alpha: 0.35),
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
    );
    return Material(
      color: dark ? Colors.black.withValues(alpha: 0.55) : Colors.white,
      elevation: 3,
      shape: const StadiumBorder(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            btn(Icons.zoom_out, 'Zoom out (Ctrl -)',
                _scale > CertificateZoomView.minScale + 0.001 ? _zoomOut : null),
            Tooltip(
              message: 'Reset to fit (Ctrl 0)',
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: _fit,
                child: SizedBox(
                  width: 52,
                  height: 36,
                  child: Center(
                    child: Text(
                      '${(_scale * 100).round()}%',
                      style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                ),
              ),
            ),
            btn(Icons.zoom_in, 'Zoom in (Ctrl +)',
                _scale < CertificateZoomView.maxScale - 0.001 ? _zoomIn : null),
            Container(width: 1, height: 22, margin: const EdgeInsets.symmetric(horizontal: 4), color: fg.withValues(alpha: 0.2)),
            btn(Icons.fit_screen_outlined, 'Fit to screen', _fit),
            if (widget.onFullscreen != null)
              btn(
                widget.fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                widget.fullscreen ? 'Exit full screen (Esc)' : 'Full screen',
                widget.onFullscreen,
              ),
          ],
        ),
      ),
    );
  }
}
