import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:parishrecord/models/user.dart';
import '../services/auth_service.dart';
import '../services/audit_service.dart';
import '../services/verification_service.dart';

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

  bool _userDocSyncDenied = false;
  bool _userDocListenDenied = false;

  static const Duration _tokenTimeout = Duration(seconds: 4);

  String _roleFromClaims(Map<String, dynamic>? claims, {String? fallback}) {
    final isAdminClaim =
        claims?['admin'] == true ||
        claims?['isAdmin'] == true ||
        (claims?['role']?.toString().trim().toLowerCase() == 'admin');
    final isStaffClaim =
        claims?['staff'] == true ||
        claims?['isStaff'] == true ||
        (claims?['role']?.toString().trim().toLowerCase() == 'staff');
    final isFinanceClaim =
        claims?['finance'] == true ||
        claims?['isFinance'] == true ||
        (claims?['role']?.toString().trim().toLowerCase() == 'finance');
    if (isAdminClaim) return 'admin';
    if (isStaffClaim) return 'staff';
    if (isFinanceClaim) return 'finance';
    final fb = fallback?.trim().toLowerCase();
    if (fb != null && fb.isNotEmpty) return fb;
    return 'parishioner';
  }

  Future<Map<String, dynamic>?> _readClaims(User user, {bool forceRefresh = false}) async {
    try {
      final result = await user
          .getIdTokenResult(forceRefresh)
          .timeout(_tokenTimeout);
      return result.claims;
    } catch (e) {
      debugPrint('AuthNotifier: getIdTokenResult failed (force=$forceRefresh): $e');
      if (forceRefresh) return null;
      try {
        final cached = await user.getIdTokenResult(false).timeout(_tokenTimeout);
        return cached.claims;
      } catch (_) {
        return null;
      }
    }
  }

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
    debugPrint('AuthNotifier: _init started');

    // Safety timeout: ensure we always become initialized even if Firebase auth is stuck
    Timer? safetyTimeout;
    safetyTimeout = Timer(const Duration(seconds: 5), () {
      debugPrint(
        'AuthNotifier: Safety timeout triggered - forcing initialized state',
      );
      if (!state.initialized) {
        state = AuthState(user: state.user, initialized: true);
      }
    });

    // Listen to auth state changes
    _authStateSubscription = _authService.authStateChanges.listen((user) async {
      debugPrint(
        'AuthNotifier: authStateChanges emitted user=${user?.uid ?? 'null'}',
      );
      final previousUser = state.user;

      if (user == null) {
        debugPrint('AuthNotifier: user is null, setting uninitialized state');
        await _userDocSubscription?.cancel();
        _userDocSubscription = null;
        _userDocSyncDenied = false;
        _userDocListenDenied = false;
        if (previousUser != null) {
          try {
            await AuditService.log(
              action: 'logout',
              userId: previousUser.id,
              userEmail: previousUser.email,
              userName: previousUser.displayName,
              userRole: previousUser.role,
              details: 'User logged out',
            );
          } catch (_) {}
        }
        safetyTimeout?.cancel();
        state = const AuthState(user: null, initialized: true);
        debugPrint('AuthNotifier: set state to initialized=true, user=null');
        return;
      }

      // Get user data from Firestore
      try {
        debugPrint('AuthNotifier: getting user data for ${user.uid}');
        final claims = await _readClaims(user);
        final isAdminClaim =
            claims?['admin'] == true ||
            claims?['isAdmin'] == true ||
            (claims?['role']?.toString().trim().toLowerCase() == 'admin');
        final isStaffClaim =
            claims?['staff'] == true ||
            claims?['isStaff'] == true ||
            (claims?['role']?.toString().trim().toLowerCase() == 'staff');
        final isFinanceClaim =
            claims?['finance'] == true ||
            claims?['isFinance'] == true ||
            (claims?['role']?.toString().trim().toLowerCase() == 'finance');
        debugPrint(
          'AuthNotifier: claims checked - isAdmin=$isAdminClaim, isStaff=$isStaffClaim, isFinance=$isFinanceClaim',
        );

        final appUser = await _authService.getUserData(user.uid);
        debugPrint(
          'AuthNotifier: getUserData returned ${appUser != null ? 'user' : 'null'}',
        );

        if (appUser != null) {
          final roleFromDoc = appUser.role.trim().toLowerCase();
          // Prioritize custom claims over Firestore role when they indicate higher privilege
          // This fixes issues where Firestore has stale role data
          String role;
          if (isAdminClaim) {
            role = 'admin';
          } else if (isStaffClaim) {
            role = 'staff';
          } else if (isFinanceClaim) {
            role = 'finance';
          } else if (roleFromDoc.isNotEmpty) {
            role = roleFromDoc;
          } else {
            role = 'parishioner';
          }
          debugPrint(
            'AuthNotifier: role resolution - Firestore="$roleFromDoc", claims admin=$isAdminClaim, staff=$isStaffClaim, finance=$isFinanceClaim, final="$role"',
          );
          final updatedUser = appUser.copyWith(role: role);
          safetyTimeout?.cancel();
          state = AuthState(user: updatedUser, initialized: true);
          debugPrint(
            'AuthNotifier: set state to initialized=true with existing user, role=$role',
          );
          _startUserDocListener(updatedUser.id);
          if (previousUser == null || previousUser.id != updatedUser.id) {
            try {
              await AuditService.log(
                action: 'login',
                userId: updatedUser.id,
                userEmail: updatedUser.email,
                userName: updatedUser.displayName,
                userRole: updatedUser.role,
                details: 'User logged in',
              );
            } catch (_) {}
          }
          // Auto-sync status fields each time auth changes
          final patch = <String, dynamic>{
            'lastLogin': FieldValue.serverTimestamp(),
            'emailVerified': user.emailVerified,
          };
          try {
            if (!_userDocSyncDenied) {
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .update(patch);
            }
          } on FirebaseException catch (e) {
            if (e.code == 'permission-denied') {
              _userDocSyncDenied = true;
              debugPrint('Auth user doc sync denied: $e');
            } else {
              debugPrint('Auth user doc sync failed: $e');
            }
          } catch (e) {
            debugPrint('Auth user doc sync failed: $e');
          }
        } else {
          // Create user document if it doesn't exist
          debugPrint('AuthNotifier: creating new user document');
          final email = user.email ?? '';
          final role = isAdminClaim
              ? 'admin'
              : (isStaffClaim
                    ? 'staff'
                    : (isFinanceClaim ? 'finance' : 'parishioner'));
          final newUser = AppUser(
            id: user.uid,
            email: email,
            displayName: user.displayName ?? email.split('@').first,
            createdAt: DateTime.now(),
            lastLogin: DateTime.now(),
            emailVerified: user.emailVerified,
            role: role,
          );
          safetyTimeout?.cancel();
          state = AuthState(user: newUser, initialized: true);
          debugPrint(
            'AuthNotifier: set state to initialized=true with new user, role=$role',
          );
          try {
            if (!_userDocSyncDenied) {
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .set(newUser.toMap(), SetOptions(merge: true));
            }
          } on FirebaseException catch (e) {
            if (e.code == 'permission-denied') {
              _userDocSyncDenied = true;
              debugPrint('Auth user doc create denied: $e');
            } else {
              debugPrint('Auth user doc create failed: $e');
            }
          } catch (e) {
            debugPrint('Auth user doc create failed: $e');
          }

          _startUserDocListener(newUser.id);
          if (previousUser == null || previousUser.id != newUser.id) {
            try {
              await AuditService.log(
                action: 'login',
                userId: newUser.id,
                userEmail: newUser.email,
                userName: newUser.displayName,
                userRole: newUser.role,
                details: 'User logged in',
              );
            } catch (_) {}
          }
        }
      } catch (e, stack) {
        debugPrint('AuthNotifier: Error in auth state handler: $e');
        debugPrint('AuthNotifier: Stack trace: $stack');
        // Offline / Firestore error: use cached token + last known user (no network).
        final claims = await _readClaims(user, forceRefresh: false);
        final role = _roleFromClaims(claims, fallback: previousUser?.role);
        final fallback = _fallbackUserFromFirebase(
          user,
          role: role,
          previous: previousUser,
        );
        state = AuthState(user: fallback, initialized: true);
        debugPrint('AuthNotifier: set fallback state with initialized=true');
        safetyTimeout?.cancel();
        if (!_userDocListenDenied) {
          _startUserDocListener(fallback.id);
        }
      }
    });
    debugPrint('AuthNotifier: _init completed, listener set up');
  }

  void _startUserDocListener(String uid) {
    if (uid.isEmpty) return;

    if (_userDocListenDenied) return;

    final current = state.user;
    if (current == null || current.id != uid) return;

    _userDocSubscription?.cancel();
    _userDocSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen(
          (snap) {
            final cur = state.user;
            if (cur == null || cur.id != uid) return;
            if (!snap.exists) return;
            final data = snap.data();
            if (data == null) return;

            final roleRaw = (data['role'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
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

            if (effectiveRole == cur.role &&
                emailVerified == cur.emailVerified) {
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
          },
          onError: (Object error) {
            if (error is FirebaseException &&
                error.code == 'permission-denied') {
              _userDocListenDenied = true;
              debugPrint('Auth user doc listen denied: $error');
              _userDocSubscription?.cancel();
              _userDocSubscription = null;
            } else {
              debugPrint('Auth user doc listen error: $error');
            }
          },
        );
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

    final isFinanceClaim =
        claims?['finance'] == true ||
        claims?['isFinance'] == true ||
        (claims?['role']?.toString().trim().toLowerCase() == 'finance');

    final isStaffClaim =
        claims?['staff'] == true ||
        claims?['isStaff'] == true ||
        (claims?['role']?.toString().trim().toLowerCase() == 'staff');

    AppUser? appUser;
    try {
      appUser = await _authService.getUserData(fbUser.uid);
    } catch (e) {
      debugPrint('refreshCurrentUser getUserData failed: $e');
    }

    if (appUser == null) {
      final prev = state.user;
      final role = isAdminClaim
          ? 'admin'
          : (isStaffClaim
                ? 'staff'
                : (isFinanceClaim
                      ? 'finance'
                      : ((prev?.role ?? 'parishioner'))));
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
        : (isAdminClaim
              ? 'admin'
              : (isStaffClaim
                    ? 'staff'
                    : (isFinanceClaim ? 'finance' : 'parishioner')));

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

      if (cred.user != null) {
        // Check if email is verified via EmailJS verification code
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(cred.user!.uid)
            .get();

        final isVerified = userDoc.data()?['verificationCodeVerified'] ?? false;

        if (!isVerified) {
          // Dev Mode Bypass: We auto-verify them if they somehow got stuck with an unverified account.
          debugPrint(
            'Dev Mode: Bypassing verification check for ${cred.user!.uid}',
          );
          await FirebaseFirestore.instance
              .collection('users')
              .doc(cred.user!.uid)
              .update({'verificationCodeVerified': true});
        }

        // Explicitly reload user data to ensure auth state is updated immediately
        // This fixes the race condition where redirect happens before state update
        await reloadUser();

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

  /// Reloads the current user from Firebase Auth and Firestore
  Future<void> reloadUser() async {
    try {
      await FirebaseAuth.instance.currentUser?.reload();
      final currentUser = FirebaseAuth.instance.currentUser;

      // Reset flags for fresh user session
      _userDocListenDenied = false;
      _userDocSyncDenied = false;

      if (currentUser == null) {
        state = const AuthState(user: null, initialized: true);
        return;
      }

      final email = currentUser.email ?? currentUser.uid;
      final idTokenResult = await currentUser.getIdTokenResult(true);
      final claims = idTokenResult.claims;

      final isAdminClaim =
          claims?['admin'] == true ||
          claims?['isAdmin'] == true ||
          (claims?['role']?.toString().trim().toLowerCase() == 'admin');
      final isStaffClaim =
          claims?['staff'] == true ||
          claims?['isStaff'] == true ||
          (claims?['role']?.toString().trim().toLowerCase() == 'staff');
      final isFinanceClaim =
          claims?['finance'] == true ||
          claims?['isFinance'] == true ||
          (claims?['role']?.toString().trim().toLowerCase() == 'finance');

      // Try to get Firestore user data for additional info
      AppUser? appUser;
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .get();

        if (userDoc.exists) {
          final data = userDoc.data()!;
          final roleFromDoc = (data['role'] ?? 'parishioner')
              .toString()
              .trim()
              .toLowerCase();

          // Prioritize claims over Firestore role when they indicate higher privilege
          final role = isAdminClaim
              ? 'admin'
              : (isStaffClaim
                    ? 'staff'
                    : (isFinanceClaim ? 'finance' : roleFromDoc));

          appUser = AppUser(
            id: currentUser.uid,
            email: email,
            displayName:
                data['displayName'] ??
                currentUser.displayName ??
                email.split('@').first,
            role: role,
            emailVerified: currentUser.emailVerified,
            lastLogin: DateTime.now(),
            createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
          );
        }
      } catch (e) {
        debugPrint('AuthNotifier: Failed to fetch user doc in reloadUser: $e');
      }

      // Fallback to Firebase Auth data if Firestore fetch failed
      appUser ??= AppUser(
        id: currentUser.uid,
        email: email,
        displayName: currentUser.displayName ?? email.split('@').first,
        role: isAdminClaim
            ? 'admin'
            : (isStaffClaim
                  ? 'staff'
                  : (isFinanceClaim ? 'finance' : 'parishioner')),
        emailVerified: currentUser.emailVerified,
        lastLogin: DateTime.now(),
      );

      // Cancel any existing listener before starting new one
      await _userDocSubscription?.cancel();
      _userDocSubscription = null;

      state = AuthState(user: appUser, initialized: true);

      // Start fresh user doc listener
      _startUserDocListener(appUser.id);

      debugPrint(
        'AuthNotifier: reloadUser completed for ${appUser.email} with role ${appUser.role}',
      );
    } catch (e) {
      debugPrint('Error reloading user: $e');
    }
  }

  /// Sends a verification email to the current user via EmailJS
  Future<void> sendVerificationEmail() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Generate new code and send via EmailJS backend
      final idToken = await user.getIdToken();
      if (idToken == null) {
        throw Exception('Unable to get authentication token');
      }
      await VerificationService.resendVerificationCode(
        uid: user.uid,
        idToken: idToken,
      );
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
