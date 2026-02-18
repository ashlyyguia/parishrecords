import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

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
      final ref = _storage.ref().child(
        'announcements/images/${docRef.id}/$imageFileName',
      );
      await ref.putData(imageBytes);
      imageUrl = await ref.getDownloadURL();
      imagePath = ref.fullPath;
    }

    String? attachmentUrl;
    String? attachmentPath;
    if (attachmentBytes != null && attachmentFileName != null) {
      final ref = _storage.ref().child(
        'announcements/attachments/${docRef.id}/$attachmentFileName',
      );
      await ref.putData(attachmentBytes);
      attachmentUrl = await ref.getDownloadURL();
      attachmentPath = ref.fullPath;
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
      if (imagePath != null) {
        await _storage.ref(imagePath).delete().catchError((_) {});
      }
      final ref = _storage.ref().child(
        'announcements/images/${announcement.id}/$newImageFileName',
      );
      await ref.putData(newImageBytes);
      imageUrl = await ref.getDownloadURL();
      imagePath = ref.fullPath;
    }

    if (newAttachmentBytes != null && newAttachmentFileName != null) {
      if (attachmentPath != null) {
        await _storage.ref(attachmentPath).delete().catchError((_) {});
      }
      final ref = _storage.ref().child(
        'announcements/attachments/${announcement.id}/$newAttachmentFileName',
      );
      await ref.putData(newAttachmentBytes);
      attachmentUrl = await ref.getDownloadURL();
      attachmentPath = ref.fullPath;
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
    final nowTs = Timestamp.fromDate(DateTime.now());
    return _col
        .where('status', isEqualTo: 'active')
        .where('eventDateTime', isGreaterThanOrEqualTo: nowTs)
        .orderBy('eventDateTime')
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((d) => Announcement.fromDoc(d)).toList(),
        );
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
