import 'dart:io';
import 'dart:developer' as developer;
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Simple script to create admin user in Firestore
// Run with: dart run scripts/create_admin_user.dart

void main(List<String> args) async {
  if (args.length < 2) {
    developer.log(
      'Usage: dart run scripts/create_admin_user.dart <email> <uid>',
    );
    developer.log(
      'Example: dart run scripts/create_admin_user.dart admin@example.com some-uid-123',
    );
    exit(1);
  }

  final email = args[0];
  final uid = args[1];

  developer.log('🔧 Creating admin user in Firestore...');

  try {
    // Initialize Firebase (you may need to adjust the config)
    await Firebase.initializeApp();

    final firestore = FirebaseFirestore.instance;

    // Create admin user document
    final adminData = {
      'id': uid,
      'email': email,
      'displayName': 'Administrator',
      'role': 'admin',
      'createdAt': FieldValue.serverTimestamp(),
      'lastLogin': FieldValue.serverTimestamp(),
      'emailVerified': true,
    };

    await firestore
        .collection('users')
        .doc(uid)
        .set(adminData, SetOptions(merge: true));

    developer.log('✅ Admin user created successfully!');
    developer.log('📧 Email: $email');
    developer.log('🆔 UID: $uid');
    developer.log('🔑 Role: admin');
  } catch (e) {
    developer.log('❌ Error creating admin user: $e');
  }

  exit(0);
}
