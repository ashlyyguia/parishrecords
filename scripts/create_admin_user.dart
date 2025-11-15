import 'dart:io';
import 'dart:developer' as developer;
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Simple script to create admin user in Firestore
// Run with: dart run scripts/create_admin_user.dart

void main() async {
  developer.log('🔧 Creating admin user in Firestore...');
  
  try {
    // Initialize Firebase (you may need to adjust the config)
    await Firebase.initializeApp();
    
    final firestore = FirebaseFirestore.instance;
    
    // Create admin user document
    final adminData = {
      'id': 'admin-user-id',
      'email': 'admin@gmail.com',
      'displayName': 'Administrator',
      'role': 'admin',
      'createdAt': FieldValue.serverTimestamp(),
      'lastLogin': FieldValue.serverTimestamp(),
      'emailVerified': true,
    };
    
    await firestore.collection('users').doc('admin-user-id').set(adminData, SetOptions(merge: true));
    
    developer.log('✅ Admin user created successfully!');
    developer.log('📧 Email: admin@gmail.com');
    developer.log('🔑 Role: admin');
    
  } catch (e) {
    developer.log('❌ Error creating admin user: $e');
  }
  
  exit(0);
}
