import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parishrecord/providers/auth_provider.dart';
import 'package:parishrecord/models/user.dart';

class AppRoles {
  static const admin = 'admin';
  static const staff = 'staff';

  /// List of all roles in order of increasing privileges
  static const List<String> allRoles = [staff, admin];

  /// Check if a user has at least the required role
  static bool hasRequiredRole(String? userRole, String requiredRole) {
    if (userRole == null) return false;
    if (userRole == requiredRole) return true;

    final userRoleIndex = allRoles.indexOf(userRole);
    final requiredRoleIndex = allRoles.indexOf(requiredRole);

    return userRoleIndex >= requiredRoleIndex;
  }

  /// Get the display name for a role
  static String displayName(String role) {
    switch (role) {
      case admin:
        return 'Administrator';
      case staff:
        return 'Staff Member';
      default:
        return role;
    }
  }
}

/// A widget that shows different content based on the user's role
class RoleBasedUI extends ConsumerWidget {
  final Widget admin;
  final Widget staff;
  final Widget fallback;

  const RoleBasedUI({
    super.key,
    required this.admin,
    required this.staff,
    required this.fallback,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;

    if (user == null) return fallback;

    switch (user.role) {
      case AppRoles.admin:
        return admin;
      case AppRoles.staff:
        return staff;
      default:
        return fallback;
    }
  }
}

/// A widget that only shows its child if the user has the required role
class AuthGuard extends ConsumerWidget {
  final Widget child;
  final String requiredRole;
  final Widget? unauthorizedChild;
  final bool checkEmailVerified;

  const AuthGuard({
    super.key,
    required this.child,
    this.requiredRole = AppRoles.staff,
    this.unauthorizedChild,
    this.checkEmailVerified = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final user = authState.user;

    // Show loading indicator while auth is initializing
    if (!authState.initialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Check if user is logged in
    if (user == null) {
      return unauthorizedChild ?? const _UnauthorizedScreen();
    }

    // Check if email needs to be verified
    if (checkEmailVerified && !user.emailVerified) {
      return _EmailNotVerifiedScreen(user: user);
    }

    // Check if user has the required role
    if (!AppRoles.hasRequiredRole(user.role, requiredRole)) {
      return unauthorizedChild ?? const _UnauthorizedScreen();
    }

    return child;
  }
}

class _UnauthorizedScreen extends StatelessWidget {
  const _UnauthorizedScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Unauthorized Access',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text('You do not have permission to view this page.'),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmailNotVerifiedScreen extends ConsumerWidget {
  final AppUser user;

  const _EmailNotVerifiedScreen({required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.email_outlined, size: 64, color: Colors.orange),
              const SizedBox(height: 24),
              Text(
                'Verify Your Email',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              const Text(
                'Please verify your email address to continue. '
                'We\'ve sent a verification email to:',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                user.email,
                style: const TextStyle(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () async {
                  // Refresh the user to check if email was verified
                  await ref.read(authProvider.notifier).reloadUser();
                },
                child: const Text('I\'ve verified my email'),
              ),
              TextButton(
                onPressed: () async {
                  try {
                    await ref
                        .read(authProvider.notifier)
                        .sendVerificationEmail();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Verification email resent!'),
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Failed to resend verification email: $e',
                          ),
                          backgroundColor: Theme.of(context).colorScheme.error,
                        ),
                      );
                    }
                  }
                },
                child: const Text('Resend verification email'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
