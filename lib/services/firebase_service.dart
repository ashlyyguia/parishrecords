import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:developer' as developer;

class FirebaseService {
  static final FirebaseAuth auth = FirebaseAuth.instance;
  static final FirebaseFirestore firestore = FirebaseFirestore.instance;
  static final FirebaseStorage storage = FirebaseStorage.instance;

  static Future<void> init() async {
    try {
      await Firebase.initializeApp();
      
      // Enable offline persistence
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
      
      // Handle authentication state changes
      auth.authStateChanges().listen((User? user) {
        if (user == null) {
          developer.log('User is currently signed out!', name: 'FirebaseService');
        } else {
          developer.log('User is signed in!', name: 'FirebaseService');
        }
      });
      
      developer.log('Firebase initialization successful', name: 'FirebaseService');
    } catch (e) {
      developer.log('Error initializing Firebase: $e', 
          name: 'FirebaseService', 
          error: e,
          stackTrace: StackTrace.current);
      rethrow;
    }
  }
}
