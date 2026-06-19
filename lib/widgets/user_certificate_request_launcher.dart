import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/user_providers.dart';

/// Opens the parishioner certificate request form only when a household
/// member has linked sacrament records.
class UserCertificateRequestLauncher {
  UserCertificateRequestLauncher._();

  static Future<bool> hasLinkedRecords(WidgetRef ref) async {
    return ref.read(userSacramentsRepositoryProvider).hasLinkedSacramentRecords();
  }

  static Future<void> open(BuildContext context, WidgetRef ref) async {
    final linked = await hasLinkedRecords(ref);
    if (!context.mounted) return;

    if (linked) {
      context.go('/records/certificate-request?user=1');
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.link_off_outlined),
        title: const Text('Link a sacrament record first'),
        content: const Text(
          'Certificate requests are only available after you add a family member '
          'in My Profile and link their baptism or confirmation record to the parish register.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.go('/user/profile');
            },
            child: const Text('Go to My Profile'),
          ),
        ],
      ),
    );
  }
}
