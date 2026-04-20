import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Service for sending verification emails via Firebase
/// Note: Email sending should be handled by Firebase Functions or Firebase Auth
class VerificationService {
  /// Send verification code email
  /// With direct Firestore, we store the verification request and rely on
  /// Firebase Auth email verification or Cloud Functions to send emails
  static Future<void> sendVerificationEmail({
    required String email,
    required String code,
    String? displayName,
  }) async {
    // Store verification code in Firestore for cloud function to process
    await FirebaseFirestore.instance.collection('verification_requests').add({
      'email': email,
      'code': code,
      'displayName': displayName,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Note: Actual email sending should be handled by a Firebase Cloud Function
    // that triggers on document creation in verification_requests collection
  }

  /// Resend verification code for a user
  static Future<void> resendVerificationCode({
    required String uid,
    required String idToken,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not authenticated');

    // Store resend request in Firestore
    await FirebaseFirestore.instance
        .collection('verification_resend_requests')
        .add({
          'uid': uid,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        });

    // Note: Actual email sending should be handled by Firebase Cloud Function
  }

  /// Request password reset link
  static Future<String?> requestPasswordResetLink(String email) async {
    await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
    return null; // Firebase Auth handles the email sending
  }
}
