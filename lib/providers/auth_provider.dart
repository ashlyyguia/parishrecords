import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:parishrecord/models/user.dart';
import '../services/auth_service.dart';
import '../services/audit_service.dart';

class AuthState {
  final AppUser? user;
  final bool initialized;
  const AuthState({this.user, this.initialized = false});
}

class AuthNotifier extends Notifier<AuthState> {
  final AuthService _authService = AuthService();
  StreamSubscription<User?>? _authStateSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _userDocSubscription;

  AppUser _fallbackUserFromFirebase(
    User fbUser, {
    required String role,
    AppUser? previous,
  }) {
    final email = fbUser.email ?? previous?.email ?? '';
    final displayName = fbUser.displayName ?? previous?.displayName;
    return AppUser(
      id: fbUser.uid,
      email: email,
      displayName:
          displayName ?? (email.isNotEmpty ? email.split('@').first : null),
      role: role,
      createdAt: previous?.createdAt,
      lastLogin: DateTime.now(),
      emailVerified: fbUser.emailVerified,
    );
  }

  @override
  AuthState build() {
    ref.onDispose(() {
      _authStateSubscription?.cancel();
      _userDocSubscription?.cancel();
    });

    _init();
    return const AuthState();
  }

  Future<void> _init() async {
    // Listen to auth state changes
    _authStateSubscription = _authService.authStateChanges.listen((user) async {
      final previousUser = state.user;

      if (user == null) {
        await _userDocSubscription?.cancel();
        _userDocSubscription = null;
        if (previousUser != null) {
          try {
            await AuditService.log(
              action: 'logout',
              userId: previousUser.id,
              details: 'User ${previousUser.email} logged out',
            );
          } catch (_) {}
        }
        state = const AuthState(user: null, initialized: true);
        return;
      }

      // Get user data from Firestore
      try {
        final idTokenResult = await user.getIdTokenResult(true);
        final claims = idTokenResult.claims;
        final isAdminClaim =
            claims?['admin'] == true ||
            claims?['isAdmin'] == true ||
            (claims?['role']?.toString().trim().toLowerCase() == 'admin');
        final appUser = await _authService.getUserData(user.uid);
        if (appUser != null) {
          final roleFromDoc = appUser.role.trim().toLowerCase();
          final role = roleFromDoc.isNotEmpty
              ? roleFromDoc
              : (isAdminClaim ? 'admin' : 'staff');
          final updatedUser = appUser.copyWith(role: role);
          state = AuthState(user: updatedUser, initialized: true);
          _startUserDocListener(updatedUser.id);
          if (previousUser == null || previousUser.id != updatedUser.id) {
            try {
              await AuditService.log(
                action: 'login',
                userId: updatedUser.id,
                details: 'User ${updatedUser.email} logged in',
              );
            } catch (_) {}
          }
          // Auto-sync status fields each time auth changes
          final patch = <String, dynamic>{
            'lastLogin': FieldValue.serverTimestamp(),
            'emailVerified': user.emailVerified,
          };
          try {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .set(patch, SetOptions(merge: true));
          } catch (e) {
            debugPrint('Auth user doc sync failed: $e');
          }
        } else {
          // Create user document if it doesn't exist
          final email = user.email ?? '';
          final role = isAdminClaim ? 'admin' : 'staff';
          final newUser = AppUser(
            id: user.uid,
            email: email,
            displayName: user.displayName ?? email.split('@').first,
            createdAt: DateTime.now(),
            lastLogin: DateTime.now(),
            emailVerified: user.emailVerified,
            role: role,
          );
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set(newUser.toMap(), SetOptions(merge: true));
          state = AuthState(user: newUser, initialized: true);
          _startUserDocListener(newUser.id);
          if (previousUser == null || previousUser.id != newUser.id) {
            try {
              await AuditService.log(
                action: 'login',
                userId: newUser.id,
                details: 'User ${newUser.email} logged in',
              );
            } catch (_) {}
          }
        }
      } catch (e) {
        debugPrint('Error in auth state changes: $e');
        try {
          final idTokenResult = await user.getIdTokenResult(true);
          final claims = idTokenResult.claims;
          final isAdminClaim =
              claims?['admin'] == true ||
              claims?['isAdmin'] == true ||
              (claims?['role']?.toString().trim().toLowerCase() == 'admin');
          final role = isAdminClaim ? 'admin' : (previousUser?.role ?? 'staff');
          final fallback = _fallbackUserFromFirebase(
            user,
            role: role,
            previous: previousUser,
          );
          state = AuthState(user: fallback, initialized: true);
          _startUserDocListener(fallback.id);
        } catch (e2) {
          debugPrint('Auth fallback user creation failed: $e2');
          state = AuthState(user: previousUser, initialized: true);
        }
      }
    });
  }

  void _startUserDocListener(String uid) {
    if (uid.isEmpty) return;

    final current = state.user;
    if (current == null || current.id != uid) return;

    _userDocSubscription?.cancel();
    _userDocSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((snap) {
          final cur = state.user;
          if (cur == null || cur.id != uid) return;
          if (!snap.exists) return;
          final data = snap.data();
          if (data == null) return;

          final roleRaw = (data['role'] ?? '').toString().trim().toLowerCase();
          bool emailVerified = cur.emailVerified;
          final ev = data['emailVerified'];
          if (ev is bool) {
            emailVerified = ev;
          }

          DateTime? lastLogin;
          final ll = data['lastLogin'];
          if (ll is Timestamp) {
            lastLogin = ll.toDate();
          } else if (ll is String) {
            lastLogin = DateTime.tryParse(ll);
          }

          final nextRole = roleRaw.isNotEmpty ? roleRaw : cur.role;

          final effectiveRole = cur.role == 'admin' ? 'admin' : nextRole;

          if (effectiveRole == cur.role && emailVerified == cur.emailVerified) {
            return;
          }

          state = AuthState(
            initialized: true,
            user: cur.copyWith(
              role: effectiveRole,
              emailVerified: emailVerified,
              lastLogin: lastLogin ?? cur.lastLogin,
            ),
          );
        });
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
    String email,
    String password,
    String displayName,
  ) async {
    try {
      await _authService.registerWithEmailAndPassword(
        email,
        password,
        displayName,
      );
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

  Future<void> refreshCurrentUser({bool forceTokenRefresh = true}) async {
    final fbUser = FirebaseAuth.instance.currentUser;
    if (fbUser == null) return;

    final idTokenResult = await fbUser.getIdTokenResult(forceTokenRefresh);
    final claims = idTokenResult.claims;
    final isAdminClaim =
        claims?['admin'] == true ||
        claims?['isAdmin'] == true ||
        (claims?['role']?.toString().trim().toLowerCase() == 'admin');

    AppUser? appUser;
    try {
      appUser = await _authService.getUserData(fbUser.uid);
    } catch (e) {
      debugPrint('refreshCurrentUser getUserData failed: $e');
    }

    if (appUser == null) {
      final prev = state.user;
      final role = isAdminClaim ? 'admin' : (prev?.role ?? 'staff');
      final fallback = _fallbackUserFromFirebase(
        fbUser,
        role: role,
        previous: prev,
      );
      state = AuthState(initialized: true, user: fallback);
      _startUserDocListener(fbUser.uid);
      return;
    }

    final roleFromDoc = appUser.role.trim().toLowerCase();
    final role = roleFromDoc.isNotEmpty
        ? roleFromDoc
        : (isAdminClaim ? 'admin' : 'staff');

    state = AuthState(
      initialized: true,
      user: appUser.copyWith(role: role, emailVerified: fbUser.emailVerified),
    );

    _startUserDocListener(fbUser.uid);

    final patch = <String, dynamic>{
      'lastLogin': FieldValue.serverTimestamp(),
      'emailVerified': fbUser.emailVerified,
    };
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(fbUser.uid)
          .set(patch, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Auth refresh user doc sync failed: $e');
    }
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
        final role = (idTokenResult.claims?['admin'] == true)
            ? 'admin'
            : 'staff';
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

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);

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
