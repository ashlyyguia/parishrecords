import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:parishrecord/models/user.dart';
import '../services/auth_service.dart';

class AuthState {
  final AppUser? user;
  final bool initialized;
  const AuthState({this.user, this.initialized = false});
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _authService = AuthService();
  StreamSubscription<User?>? _authStateSubscription;

  AuthNotifier() : super(const AuthState()) {
    _init();
  }

  Future<void> _init() async {
    // Listen to auth state changes
    _authStateSubscription = _authService.authStateChanges.listen((user) async {
      if (user == null) {
        state = const AuthState(user: null, initialized: true);
        return;
      }

      // Get user data from Firestore
      try {
        final idTokenResult = await user.getIdTokenResult(true);
        final isAdmin = (idTokenResult.claims?['admin'] == true) || (user.email?.toLowerCase() == 'admin@gmail.com');
        final appUser = await _authService.getUserData(user.uid);
        if (appUser != null) {
          state = AuthState(user: appUser.copyWith(role: isAdmin ? 'admin' : 'staff'), initialized: true);
          // Auto-sync status fields each time auth changes
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
            'lastLogin': FieldValue.serverTimestamp(),
            'emailVerified': user.emailVerified,
            'role': isAdmin ? 'admin' : 'staff',
          }, SetOptions(merge: true));
        } else {
          // Create user document if it doesn't exist
          final email = user.email ?? '';
          final role = isAdmin ? 'admin' : 'staff';
          final newUser = AppUser(
            id: user.uid,
            email: email,
            displayName: user.displayName ?? email.split('@').first,
            createdAt: DateTime.now(),
            lastLogin: DateTime.now(),
            emailVerified: user.emailVerified,
            role: role,
          );
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set(newUser.toMap(), SetOptions(merge: true));
          state = AuthState(user: newUser, initialized: true);
        }
      } catch (e) {
        debugPrint('Error in auth state changes: $e');
        state = const AuthState(user: null, initialized: true);
      }
    });
  }

  @override
  void dispose() {
    _authStateSubscription?.cancel();
    super.dispose();
  }

  // Sign in with email and password
  Future<void> signInWithEmailAndPassword(String email, String password) async {
    try {
      await _authService.signInWithEmailAndPassword(email, password);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthError(e);
    }
  }

  // Register with email and password
  Future<void> registerWithEmailAndPassword(
      String email, String password, String displayName) async {
    try {
      await _authService.registerWithEmailAndPassword(email, password, displayName);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthError(e);
    }
  }

  // Google Sign-In not used in this app

  // Sign out
  Future<void> signOut() async {
    await _authService.signOut();
    state = const AuthState(user: null, initialized: true);
  }

  // Reset password
  Future<void> resetPassword(String email) async {
    try {
      await _authService.sendPasswordResetEmail(email);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthError(e);
    }
  }

  // Update user profile
  Future<void> updateProfile({
    required String uid,
    String? displayName,
    String? photoURL,
  }) async {
    try {
      await _authService.updateProfile(
        uid: uid,
        displayName: displayName,
        photoURL: photoURL,
      );
      // Update local state with new values if present
      if (state.user != null) {
        final updated = state.user!.copyWith(
          displayName: displayName ?? state.user!.displayName,
        );
        state = AuthState(user: updated, initialized: true);
      }
    } on FirebaseAuthException catch (e) {
      throw _handleAuthError(e);
    } catch (_) {
      rethrow;
    }
  }

  /// Logs in a user with email and password
  /// Returns a tuple of (success, message)
  Future<(bool, String)> login(String email, String password) async {
    if (email.isEmpty || password.isEmpty) {
      return (false, 'Please enter both email and password');
    }
    
    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      
      // The auth state listener will handle the state update
      if (cred.user != null) {
        return (true, 'Login successful');
      }
      return (false, 'Login failed. Please try again.');
      
    } on FirebaseAuthException catch (e) {
      String message = 'Login failed';
      switch (e.code) {
        case 'user-not-found':
          message = 'No user found with this email.';
          break;
        case 'wrong-password':
          message = 'Incorrect password. Please try again.';
          break;
        case 'user-disabled':
          message = 'This account has been disabled.';
          break;
        case 'invalid-email':
          message = 'The email address is not valid.';
          break;
        default:
          message = e.message ?? 'An unknown error occurred';
      }
      debugPrint('Login error: ${e.code} - $message');
      return (false, message);
    } catch (e) {
      debugPrint('Unexpected login error: $e');
      return (false, 'An unexpected error occurred. Please try again.');
    }
  }

  Future<void> logout() async {
    await _authService.signOut();
    state = const AuthState(initialized: true);
  }


  /// Reloads the current user from Firebase Auth
  Future<void> reloadUser() async {
    try {
      await FirebaseAuth.instance.currentUser?.reload();
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        final email = currentUser.email ?? currentUser.uid;
        final idTokenResult = await currentUser.getIdTokenResult(true);
        final role = (idTokenResult.claims?['admin'] == true) ? 'admin' : 'staff';
        final appUser = AppUser(
          id: currentUser.uid,
          email: email,
          displayName: currentUser.displayName,
          role: role,
          emailVerified: currentUser.emailVerified,
          lastLogin: DateTime.now(),
        );
        state = AuthState(user: appUser, initialized: true);
      }
    } catch (e) {
      debugPrint('Error reloading user: $e');
    }
  }

  /// Sends a verification email to the current user
  Future<void> sendVerificationEmail() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && !user.emailVerified) {
        await user.sendEmailVerification();
      }
    } catch (e) {
      debugPrint('Error sending verification email: $e');
      rethrow;
    }
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});

extension _AuthError on AuthNotifier {
  String _handleAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No user found with this email.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'The password provided is too weak.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many requests. Please try again later.';
      case 'operation-not-allowed':
        return 'This operation is not allowed. Please contact support.';
      case 'requires-recent-login':
        return 'Please log in again to perform this operation.';
      default:
        return e.message ?? 'An error occurred. Please try again.';
    }
  }
}
