import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../models/announcement.dart';

class AnnouncementsRepository {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  String _requireUid() {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;
    if (uid == null || uid.isEmpty) {
      throw Exception('Not authenticated');
    }
    return uid;
  }

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('announcements');

  String? _encodeImage(Uint8List? bytes) {
    if (bytes == null) return null;
    try {
      final image = img.decodeImage(bytes);
      if (image == null) return null;

      var resized = image;
      if (image.width > 800 || image.height > 800) {
        resized = img.copyResize(image,
            width: image.width > image.height ? 800 : null,
            height: image.height >= image.width ? 800 : null);
      }

      final compressedBytes = img.encodeJpg(resized, quality: 70);
      final base64String = base64Encode(compressedBytes);
      return 'data:image/jpeg;base64,$base64String';
    } catch (e) {
      debugPrint('Error encoding image: $e');
      return null;
    }
  }

  String? _encodePdf(Uint8List? bytes) {
    if (bytes == null) return null;
    if (bytes.length > 500 * 1024) {
      throw Exception(
          'PDF attachment is too large. Maximum size is 500KB when using database storage.');
    }
    final base64String = base64Encode(bytes);
    return 'data:application/pdf;base64,$base64String';
  }

  Future<Announcement> create({
    required String title,
    required String description,
    required DateTime eventDateTime,
    required String location,
    String status = 'draft',
    bool pinned = false,
    String announcementType = 'general',
    String? person1Name,
    String? person2Name,
    Uint8List? imageBytes,
    String? imageFileName,
    Uint8List? image2Bytes,
    String? image2FileName,
    Uint8List? attachmentBytes,
    String? attachmentFileName,
  }) async {
    final uid = _requireUid();
    final now = DateTime.now();
    final docRef = _col.doc();

    final imageUrl = _encodeImage(imageBytes);
    final imageUrl2 = _encodeImage(image2Bytes);
    final attachmentUrl = _encodePdf(attachmentBytes);

    final ann = Announcement(
      id: docRef.id,
      title: title,
      description: description,
      imageUrl: imageUrl,
      imageStoragePath: null, // No longer using Firebase Storage
      imageUrl2: imageUrl2,
      imageStoragePath2: null,
      attachmentUrl: attachmentUrl,
      attachmentStoragePath: null,
      person1Name: person1Name,
      person2Name: person2Name,
      eventDateTime: eventDateTime,
      location: location,
      status: status,
      pinned: pinned,
      createdByUid: uid,
      createdAt: now,
      updatedAt: now,
      views: 0,
      announcementType: announcementType,
    );

    await docRef.set(ann.toMap());
    return ann;
  }

  Future<void> update(
    Announcement announcement, {
    Uint8List? newImageBytes,
    String? newImageFileName,
    Uint8List? newImage2Bytes,
    String? newImage2FileName,
    Uint8List? newAttachmentBytes,
    String? newAttachmentFileName,
  }) async {
    String? imageUrl = announcement.imageUrl;
    String? imageUrl2 = announcement.imageUrl2;
    String? attachmentUrl = announcement.attachmentUrl;

    if (newImageBytes != null) {
      imageUrl = _encodeImage(newImageBytes);
    }
    if (newImage2Bytes != null) {
      imageUrl2 = _encodeImage(newImage2Bytes);
    }
    if (newAttachmentBytes != null) {
      attachmentUrl = _encodePdf(newAttachmentBytes);
    }

    // simple auto-archive
    final now = DateTime.now();
    String status = announcement.status;
    if (announcement.eventDateTime.isBefore(now) && status == 'active') {
      status = 'archived';
    }

    final updated = announcement.copyWith(
      imageUrl: imageUrl,
      imageStoragePath: null,
      imageUrl2: imageUrl2,
      imageStoragePath2: null,
      attachmentUrl: attachmentUrl,
      attachmentStoragePath: null,
      status: status,
      updatedAt: now,
    );

    await _col.doc(announcement.id).update(updated.toMap());
  }

  Future<void> delete(Announcement announcement) async {
    // No storage paths to delete anymore
    await _col.doc(announcement.id).delete();
  }

  Stream<List<Announcement>> watchAdminList() {
    return _col
        .orderBy('pinned', descending: true)
        .orderBy('eventDateTime')
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((d) => Announcement.fromDoc(d)).toList(),
        );
  }

  Stream<List<Announcement>> watchPublicActive() {
    return _col
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((snapshot) {
      final announcements =
          snapshot.docs.map((d) => Announcement.fromDoc(d)).toList();
      // Sort by eventDateTime in memory
      announcements.sort((a, b) => a.eventDateTime.compareTo(b.eventDateTime));
      return announcements;
    });
  }

  Future<Announcement?> loadById(String id) async {
    final doc = await _col.doc(id).get();
    if (!doc.exists) return null;
    return Announcement.fromDoc(doc);
  }

  Future<void> incrementViews(String id) async {
    await _col.doc(id).update({'views': FieldValue.increment(1)});
  }
}
