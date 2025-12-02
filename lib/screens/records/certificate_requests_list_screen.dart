import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../services/requests_repository.dart';

class CertificateRequestsListScreen extends ConsumerStatefulWidget {
  const CertificateRequestsListScreen({super.key});

  @override
  ConsumerState<CertificateRequestsListScreen> createState() =>
      _CertificateRequestsListScreenState();
}

class _CertificateRequestsListScreenState
    extends ConsumerState<CertificateRequestsListScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = RequestsRepository().list(limit: 100);
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'pending':
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final df = DateFormat.yMd();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Certificate Requests'),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await context.push('/records/certificate-request');
              setState(() {
                _future = RequestsRepository().list(limit: 100);
              });
            },
            icon: const Icon(Icons.add),
            label: const Text('New Request'),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Failed to load requests',
                style: TextStyle(color: colorScheme.error),
              ),
            );
          }
          final rows = snapshot.data ?? const [];
          if (rows.isEmpty) {
            return Center(
              child: Text(
                'No certificate requests',
                style: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            );
          }

          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final r = rows[index];
              final status = (r['status']?.toString() ?? 'pending');
              final type = (r['request_type']?.toString() ?? '').toUpperCase();
              final requester = (r['requester_name']?.toString() ?? '');
              final requestedAt = r['requested_at'];
              String subtitle;
              if (requestedAt is String) {
                subtitle = df.format(
                  DateTime.tryParse(requestedAt) ?? DateTime.now(),
                );
              } else if (requestedAt is DateTime) {
                subtitle = df.format(requestedAt);
              } else {
                subtitle = '';
              }
              final recordId = r['record_id']?.toString();

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: _statusColor(status).withValues(alpha: 0.1),
                  child: Icon(
                    Icons.request_page_outlined,
                    color: _statusColor(status),
                  ),
                ),
                title: Text(
                  requester.isEmpty ? 'Certificate Request' : requester,
                ),
                subtitle: Text(
                  type.isEmpty
                      ? subtitle
                      : [type, if (subtitle.isNotEmpty) subtitle].join(' • '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor(status).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: _statusColor(status),
                    ),
                  ),
                ),
                onTap: recordId == null || recordId.isEmpty
                    ? null
                    : () => context.push('/records/$recordId'),
              );
            },
          );
        },
      ),
    );
  }
}
