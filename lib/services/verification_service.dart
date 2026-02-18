import 'package:firebase_auth/firebase_auth.dart';

class VerificationService {
  static Future<void> sendCode(String email, String code) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Not authenticated');
    }
    throw UnsupportedError('Firebase-only: sendCode is not available');
  }
}
