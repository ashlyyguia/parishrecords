import 'dart:convert';
import 'package:flutter/material.dart';

class SafeImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Alignment alignment;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;

  const SafeImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
    this.errorBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl.startsWith('data:image')) {
      try {
        final base64Str = imageUrl.split(',').last;
        return Image.memory(
          base64Decode(base64Str),
          width: width,
          height: height,
          fit: fit,
          alignment: alignment,
          errorBuilder: errorBuilder,
        );
      } catch (e) {
        if (errorBuilder != null) {
          return errorBuilder!(context, e, null);
        }
        return _fallback(context);
      }
    }
    return Image.network(
      imageUrl,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      errorBuilder: errorBuilder ?? (_, __, ___) => _fallback(context),
    );
  }

  Widget _fallback(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: Colors.grey.shade200,
      child: Icon(Icons.image_not_supported, color: Colors.grey.shade400),
    );
  }
}
