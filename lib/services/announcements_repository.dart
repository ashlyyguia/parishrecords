// ignore_for_file: unnecessary_import

import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../models/announcement.dart';

class AnnouncementsRepository {
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  FirebaseStorage get _storage => FirebaseStorage.instance;

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

  Future<Announcement> create({
    required String title,
    required String description,
    required DateTime eventDateTime,
    required String location,
    String status = 'draft',
    bool pinned = false,
    Uint8List? imageBytes,
    String? imageFileName,
    Uint8List? attachmentBytes,
    String? attachmentFileName,
  }) async {
    final uid = _requireUid();
    final now = DateTime.now();
    final docRef = _col.doc();

    String? imageUrl;
    String? imagePath;
    if (imageBytes != null && imageFileName != null) {
      try {
        final ref = _storage.ref().child(
          'announcements/images/${docRef.id}/$imageFileName',
        );
        await ref.putData(imageBytes);
        imageUrl = await ref.getDownloadURL();
        imagePath = ref.fullPath;
      } catch (e) {
        // Storage not available - continue without image
        debugPrint('Storage upload failed (no storage enabled): $e');
      }
    }

    String? attachmentUrl;
    String? attachmentPath;
    if (attachmentBytes != null && attachmentFileName != null) {
      try {
        final ref = _storage.ref().child(
          'announcements/attachments/${docRef.id}/$attachmentFileName',
        );
        await ref.putData(attachmentBytes);
        attachmentUrl = await ref.getDownloadURL();
        attachmentPath = ref.fullPath;
      } catch (e) {
        // Storage not available - continue without attachment
        debugPrint('Storage upload failed (no storage enabled): $e');
      }
    }

    final ann = Announcement(
      id: docRef.id,
      title: title,
      description: description,
      imageUrl: imageUrl,
      imageStoragePath: imagePath,
      attachmentUrl: attachmentUrl,
      attachmentStoragePath: attachmentPath,
      eventDateTime: eventDateTime,
      location: location,
      status: status,
      pinned: pinned,
      createdByUid: uid,
      createdAt: now,
      updatedAt: now,
      views: 0,
    );

    await docRef.set(ann.toMap());
    return ann;
  }

  Future<void> update(
    Announcement announcement, {
    Uint8List? newImageBytes,
    String? newImageFileName,
    Uint8List? newAttachmentBytes,
    String? newAttachmentFileName,
  }) async {
    String? imageUrl = announcement.imageUrl;
    String? imagePath = announcement.imageStoragePath;
    String? attachmentUrl = announcement.attachmentUrl;
    String? attachmentPath = announcement.attachmentStoragePath;

    if (newImageBytes != null && newImageFileName != null) {
      try {
        if (imagePath != null) {
          await _storage.ref(imagePath).delete().catchError((_) {});
        }
        final ref = _storage.ref().child(
          'announcements/images/${announcement.id}/$newImageFileName',
        );
        await ref.putData(newImageBytes);
        imageUrl = await ref.getDownloadURL();
        imagePath = ref.fullPath;
      } catch (e) {
        // Storage not available - keep existing image data
        debugPrint('Storage upload failed (no storage enabled): $e');
      }
    }

    if (newAttachmentBytes != null && newAttachmentFileName != null) {
      try {
        if (attachmentPath != null) {
          await _storage.ref(attachmentPath).delete().catchError((_) {});
        }
        final ref = _storage.ref().child(
          'announcements/attachments/${announcement.id}/$newAttachmentFileName',
        );
        await ref.putData(newAttachmentBytes);
        attachmentUrl = await ref.getDownloadURL();
        attachmentPath = ref.fullPath;
      } catch (e) {
        // Storage not available - keep existing attachment data
        debugPrint('Storage upload failed (no storage enabled): $e');
      }
    }

    // simple auto-archive
    final now = DateTime.now();
    String status = announcement.status;
    if (announcement.eventDateTime.isBefore(now) && status == 'active') {
      status = 'archived';
    }

    final updated = announcement.copyWith(
      imageUrl: imageUrl,
      imageStoragePath: imagePath,
      attachmentUrl: attachmentUrl,
      attachmentStoragePath: attachmentPath,
      status: status,
      updatedAt: now,
    );

    await _col.doc(announcement.id).update(updated.toMap());
  }

  Future<void> delete(Announcement announcement) async {
    if (announcement.imageStoragePath != null) {
      await _storage
          .ref(announcement.imageStoragePath!)
          .delete()
          .catchError((_) {});
    }
    if (announcement.attachmentStoragePath != null) {
      await _storage
          .ref(announcement.attachmentStoragePath!)
          .delete()
          .catchError((_) {});
    }
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
    // Use a controller to properly handle errors without breaking the stream
    final controller = StreamController<List<Announcement>>.broadcast();

    // Emit empty list immediately so page loads without waiting
    controller.add(<Announcement>[]);

    // Simplified query without orderBy to avoid composite index issues
    // Just filter by status and sort in memory
    _col
        .where('status', isEqualTo: 'active')
        .snapshots()
        .listen(
          (snapshot) {
            try {
              final announcements = snapshot.docs
                  .map((d) => Announcement.fromDoc(d))
                  .toList();
              // Sort by eventDateTime in memory
              announcements.sort(
                (a, b) => a.eventDateTime.compareTo(b.eventDateTime),
              );
              controller.add(announcements);
            } catch (e) {
              debugPrint('Error parsing announcements: $e');
              controller.add(<Announcement>[]);
            }
          },
          onError: (error) {
            debugPrint('Firestore query error: $error');
            controller.add(<Announcement>[]);
          },
        );

    return controller.stream;
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
