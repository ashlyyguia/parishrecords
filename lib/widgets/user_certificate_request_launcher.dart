import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/user_providers.dart';

/// Opens the parishioner certificate request form.
class UserCertificateRequestLauncher {
  UserCertificateRequestLauncher._();

  static Future<bool> hasLinkedRecords(WidgetRef ref) async {
    return ref.read(userSacramentsRepositoryProvider).hasLinkedSacramentRecords();
  }

  /// Always opens the form. Requests without a linked record are sent with
  /// the details the parishioner types, and the office verifies them.
  static Future<void> open(BuildContext context, WidgetRef ref) async {
    if (!context.mounted) return;
    context.go('/records/certificate-request?user=1');
  }
}
