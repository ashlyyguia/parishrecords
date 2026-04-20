import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/parish_event.dart';

class EventsRepository {
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
      _db.collection('events');

  Future<ParishEvent> create({
    required String title,
    required String description,
    required String location,
    required String eventType,
    DateTime? eventDateTime,
    DateTime? eventEndDateTime,
    String? recurrencePattern,
    List<String>? recurrenceDays,
    String? recurrenceTime,
    String? recurrenceEndTime,
    String status = 'draft',
    bool pinned = false,
    Uint8List? imageBytes,
    String? imageFileName,
  }) async {
    final uid = _requireUid();
    final now = DateTime.now();
    final docRef = _col.doc();

    String? imageUrl;
    String? imagePath;
    if (imageBytes != null && imageFileName != null) {
      final ref = _storage.ref().child(
        'events/images/${docRef.id}/$imageFileName',
      );
      await ref.putData(imageBytes);
      imageUrl = await ref.getDownloadURL();
      imagePath = ref.fullPath;
    }

    final event = ParishEvent(
      id: docRef.id,
      title: title,
      description: description,
      imageUrl: imageUrl,
      imageStoragePath: imagePath,
      location: location,
      eventType: eventType,
      eventDateTime: eventDateTime,
      eventEndDateTime: eventEndDateTime,
      recurrencePattern: recurrencePattern,
      recurrenceDays: recurrenceDays,
      recurrenceTime: recurrenceTime,
      recurrenceEndTime: recurrenceEndTime,
      status: status,
      pinned: pinned,
      createdByUid: uid,
      createdAt: now,
      updatedAt: now,
    );

    await docRef.set(event.toMap());
    return event;
  }

  Future<void> update(
    ParishEvent event, {
    Uint8List? newImageBytes,
    String? newImageFileName,
  }) async {
    String? imageUrl = event.imageUrl;
    String? imagePath = event.imageStoragePath;

    if (newImageBytes != null && newImageFileName != null) {
      if (imagePath != null) {
        await _storage.ref(imagePath).delete().catchError((_) {});
      }
      final ref = _storage.ref().child(
        'events/images/${event.id}/$newImageFileName',
      );
      await ref.putData(newImageBytes);
      imageUrl = await ref.getDownloadURL();
      imagePath = ref.fullPath;
    }

    final updated = event.copyWith(
      imageUrl: imageUrl,
      imageStoragePath: imagePath,
      updatedAt: DateTime.now(),
    );

    await _col.doc(event.id).update(updated.toMap());
  }

  Future<void> delete(ParishEvent event) async {
    if (event.imageStoragePath != null) {
      await _storage.ref(event.imageStoragePath!).delete().catchError((_) {});
    }
    await _col.doc(event.id).delete();
  }

  /// Watch all active events for public display (both one-time and recurring)
  Stream<List<ParishEvent>> watchPublicActive() {
    return _col.where('status', isEqualTo: 'active').snapshots().map((
      snapshot,
    ) {
      final items = snapshot.docs.map((d) => ParishEvent.fromDoc(d)).toList();
      items.sort((a, b) {
        final pin = (b.pinned ? 1 : 0) - (a.pinned ? 1 : 0);
        if (pin != 0) return pin;
        final aCreated = a.createdAt;
        final bCreated = b.createdAt;
        return bCreated.compareTo(aCreated);
      });
      return items;
    });
  }

  /// Watch upcoming one-time events (eventDateTime >= now)
  Stream<List<ParishEvent>> watchUpcomingOneTime() {
    final nowTs = Timestamp.fromDate(DateTime.now());
    return _col
        .where('status', isEqualTo: 'active')
        .where('eventType', isEqualTo: 'one-time')
        .where('eventDateTime', isGreaterThanOrEqualTo: nowTs)
        .orderBy('eventDateTime')
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((d) => ParishEvent.fromDoc(d)).toList(),
        );
  }

  /// Watch recurring events
  Stream<List<ParishEvent>> watchRecurring() {
    return _col
        .where('status', isEqualTo: 'active')
        .where('eventType', isEqualTo: 'recurring')
        .orderBy('pinned', descending: true)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((d) => ParishEvent.fromDoc(d)).toList(),
        );
  }

  Stream<List<ParishEvent>> watchAdminList() {
    return _col
        .orderBy('pinned', descending: true)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((d) => ParishEvent.fromDoc(d)).toList(),
        );
  }

  Future<ParishEvent?> loadById(String id) async {
    final doc = await _col.doc(id).get();
    if (!doc.exists) return null;
    return ParishEvent.fromDoc(doc);
  }
}
