import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image/image.dart' as img;

/// The Parish Priest/Vicar e-signature printed on certificates.
///
/// Stored as a PNG (base64) in `settings/certificate_signature`. Firebase
/// Storage is not used in this deployment, and a cleaned signature is small
/// (tens of KB), well under Firestore's 1 MiB document limit. Only admins
/// may write it; only admin and staff may read it (see firestore.rules).
class CertificateSignatureService {
  CertificateSignatureService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const _collection = 'settings';
  static const _docId = 'certificate_signature';

  DocumentReference<Map<String, dynamic>> get _doc =>
      _db.collection(_collection).doc(_docId);

  /// Returns the stored signature PNG, or null when none is set.
  Future<Uint8List?> load() async {
    final snap = await _doc.get();
    final b64 = snap.data()?['image_b64'];
    if (b64 is! String || b64.isEmpty) return null;
    try {
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  /// Cleans [raw] (see [prepare]) and saves it. Returns the stored PNG.
  Future<Uint8List> save(Uint8List raw) async {
    final png = prepare(raw);
    final user = FirebaseAuth.instance.currentUser;
    await _doc.set({
      'image_b64': base64Encode(png),
      'updated_at': FieldValue.serverTimestamp(),
      'updated_by_uid': user?.uid,
      'updated_by': user?.displayName ?? user?.email,
    });
    return png;
  }

  Future<void> clear() => _doc.delete();

  /// Turns a photo or scan of a signature into a transparent PNG:
  /// paper-white pixels become transparent, the ink is cropped to its
  /// bounding box, and the result is scaled to at most 600 px wide.
  ///
  /// Throws [FormatException] when the bytes are not an image or contain
  /// no visible ink.
  static Uint8List prepare(Uint8List raw) {
    img.Image? image;
    try {
      image = img.decodeImage(raw);
    } catch (_) {
      image = null; // truncated or unsupported file
    }
    if (image == null) {
      throw const FormatException('That file is not an image.');
    }
    if (image.width > 1600) image = img.copyResize(image, width: 1600);
    image = image.convert(numChannels: 4);

    // Paper is the bright background; anything clearly darker is ink.
    // Pixels in between fade out so strokes keep smooth edges.
    const inkMax = 150.0; // luminance at or below: fully opaque
    const paperMin = 205.0; // luminance at or above: fully transparent
    var minX = image.width, minY = image.height, maxX = -1, maxY = -1;
    for (final p in image) {
      final lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      double alpha;
      if (lum <= inkMax) {
        alpha = 1;
      } else if (lum >= paperMin) {
        alpha = 0;
      } else {
        alpha = (paperMin - lum) / (paperMin - inkMax);
      }
      alpha *= p.a / 255.0; // keep existing transparency
      final a = (alpha * 255).round();
      p.a = a;
      if (a > 40) {
        if (p.x < minX) minX = p.x;
        if (p.x > maxX) maxX = p.x;
        if (p.y < minY) minY = p.y;
        if (p.y > maxY) maxY = p.y;
      }
    }
    if (maxX < 0) {
      throw const FormatException(
        'No signature was found in that image. Use dark ink on white paper.',
      );
    }
    const pad = 6;
    final x0 = (minX - pad).clamp(0, image.width - 1);
    final y0 = (minY - pad).clamp(0, image.height - 1);
    final x1 = (maxX + pad).clamp(0, image.width - 1);
    final y1 = (maxY + pad).clamp(0, image.height - 1);
    var out = img.copyCrop(
      image,
      x: x0,
      y: y0,
      width: x1 - x0 + 1,
      height: y1 - y0 + 1,
    );
    if (out.width > 600) out = img.copyResize(out, width: 600);
    return Uint8List.fromList(img.encodePng(out, level: 9));
  }
}
