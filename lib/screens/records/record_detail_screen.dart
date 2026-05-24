import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../models/record.dart';
import '../../models/register_marriage_entry.dart';
import '../../providers/records_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/records_repository.dart';
import '../../utils/manual_register_notes.dart';

class RecordDetailScreen extends ConsumerWidget {
  final String recordId;
  const RecordDetailScreen({super.key, required this.recordId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordAsync = ref.watch(recordByIdProvider(recordId));

    return recordAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Record')),
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Record')),
        body: Center(child: Text('Failed to load record: $e')),
      ),
      data: (rec) {
        if (rec == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Record')),
            body: const Center(child: Text('Record not found')),
          );
        }
        return _RecordDetailBody(rec: rec);
      },
    );
  }
}

bool _isAdminRecordsContext(BuildContext context) {
  return GoRouterState.of(context).uri.path.startsWith('/admin/records');
}

class _RecordDetailBody extends ConsumerWidget {
  const _RecordDetailBody({required this.rec});

  final ParishRecord rec;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final adminContext = _isAdminRecordsContext(context);
    final canDelete = user?.role == 'admin';
    final isStaffOrAdmin = user?.role == 'admin' || user?.role == 'staff';

    final df = DateFormat.yMMMMd();
    Map<String, dynamic>? decodedNotes;
    if (rec.notes != null && rec.notes!.trim().startsWith('{')) {
      try {
        decodedNotes = json.decode(rec.notes!) as Map<String, dynamic>;
      } catch (_) {
        decodedNotes = null;
      }
    }
    final additional = _extractAdditionalInfo(rec, decodedNotes);
    final hasCert = additional.certificateIssued;

    return Scaffold(
      appBar: AppBar(
        title: Text(rec.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () {
              switch (rec.type) {
                case RecordType.baptism:
                  if (ManualRegisterNotes.isManualBaptismRecord(rec)) {
                    context.push(
                      adminContext
                          ? '/admin/records/manual-baptism'
                          : '/staff/records/manual-baptism',
                      extra: rec,
                    );
                  } else {
                    context.push(
                      adminContext
                          ? '/admin/records/new/baptism'
                          : '/records/new/baptism',
                      extra: rec,
                    );
                  }
                  break;
                case RecordType.marriage:
                  if (ManualRegisterNotes.isManualMarriageRecord(rec)) {
                    context.push(
                      adminContext
                          ? '/admin/records/manual-marriage'
                          : '/staff/records/manual-marriage',
                      extra: rec,
                    );
                  } else {
                    context.push(
                      adminContext
                          ? '/admin/records/new/marriage'
                          : '/records/new/marriage',
                      extra: rec,
                    );
                  }
                  break;
                case RecordType.confirmation:
                  context.push(
                    adminContext
                        ? '/admin/records/new/confirmation'
                        : '/records/new/confirmation',
                    extra: rec,
                  );
                  break;
                case RecordType.funeral:
                  context.push(
                    adminContext
                        ? '/admin/records/new/death'
                        : '/records/new/death',
                    extra: rec,
                  );
                  break;
              }
            },
          ),
          if (isStaffOrAdmin)
            IconButton(
              tooltip: 'Generate Certificate',
              icon: const Icon(Icons.card_membership),
              onPressed: () {
                context.push(
                  adminContext
                      ? '/admin/records/${rec.id}/certificate'
                      : '/records/${rec.id}/certificate',
                  extra: rec.type,
                );
              },
            ),
          if (canDelete)
            PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'delete') {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('Delete record?'),
                      content: Text('This will delete "${rec.name}"'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(c).pop(false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(c).pop(true),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );

                  if (ok == true) {
                    try {
                      await RecordsRepository().deleteForType(rec.id, rec.type);
                      await ref.read(recordsProvider.notifier).load();
                      if (context.mounted) {
                        context.pop();
                      }
                    } catch (err) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Failed to delete record. It may have been removed on the server. (${err.toString()})',
                          ),
                        ),
                      );
                    }
                  }
                }
              },
              itemBuilder: (c) => const [
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (rec.imagePath != null) ...[
            kIsWeb
                ? const SizedBox(
                    height: 180,
                    child: Center(
                      child: Text('Image preview not available on web'),
                    ),
                  )
                : AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.file(File(rec.imagePath!), fit: BoxFit.cover),
                  ),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                rec.name,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Chip(label: Text(_capitalize(rec.type.name))),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.calendar_today_outlined,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(df.format(rec.date)),
                                    ],
                                  ),
                                  if (hasCert)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Text(
                                        'CERT ISSUED',
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  if (rec.parish != null &&
                                      rec.parish!.isNotEmpty)
                                    Text(
                                      rec.parish!,
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.7),
                                      ),
                                    ),
                                ],
                              ),
                              if (rec.id.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  'Record ID: ${rec.id}',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.6),
                                      ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (rec.parish != null && rec.parish!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.church_outlined),
                      title: const Text('Parish'),
                      subtitle: Text(rec.parish!),
                    ),
                  ),
                ],
                if (decodedNotes != null) ...[
                  const SizedBox(height: 16),
                  _buildStructuredDetails(context, rec, decodedNotes, df),
                ] else if (rec.notes != null &&
                    rec.notes!.trim().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Details / Notes',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          SelectableText(rec.notes!),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: isStaffOrAdmin
          ? FloatingActionButton.extended(
              onPressed: () {
                context.push('/records/${rec.id}/certificate', extra: rec.type);
              },
              icon: const Icon(Icons.card_membership),
              label: const Text('Certificate'),
            )
          : null,
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Widget _buildStructuredDetails(
    BuildContext context,
    ParishRecord rec,
    Map<String, dynamic> data,
    DateFormat df,
  ) {
    switch (rec.type) {
      case RecordType.baptism:
        return _buildBaptismDetails(context, data, df);
      case RecordType.marriage:
        return _buildMarriageDetails(context, data, df);
      case RecordType.confirmation:
        return _buildConfirmationDetails(context, data, df);
      case RecordType.funeral:
        return _buildDeathDetails(context, data, df);
    }
  }

  Widget _buildBaptismDetails(
    BuildContext context,
    Map<String, dynamic> data,
    DateFormat df,
  ) {
    if (ManualRegisterNotes.usesFlatRegisterLayout(data)) {
      return _buildFlatRegisterBaptismDetails(context, data);
    }

    final registry = _asMap(data['registry']);
    final child = _asMap(data['child']);
    final parents = _asMap(data['parents']);
    final godparents = _asMap(data['godparents']);
    final baptism = _asMap(data['baptism']);
    final metadata = _asMap(data['metadata']);
    final parentsText = parents == null ? _parentsAsText(data['parents']) : null;

    String fmtDate(String? iso) {
      if (iso == null || iso.isEmpty) return '';
      final d = DateTime.tryParse(iso);
      if (d == null) return iso;
      return df.format(d);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (registry != null) ...[
              const Text(
                'Registry Information',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              if (registry['registryNo'] != null)
                Text('Registry No: ${registry['registryNo']}'),
              if (registry['bookNo'] != null)
                Text('Book No: ${registry['bookNo']}'),
              if (registry['pageNo'] != null)
                Text('Page No: ${registry['pageNo']}'),
              if (registry['lineNo'] != null)
                Text('Line No: ${registry['lineNo']}'),
              const SizedBox(height: 12),
            ],
            if (child != null) ...[
              const Text(
                'Child Information',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              if (child['fullName'] != null) Text('Name: ${child['fullName']}'),
              if (child['dateOfBirth'] != null)
                Text(
                  'Date of Birth: ${fmtDate(child['dateOfBirth']?.toString())}',
                ),
              if (child['placeOfBirth'] != null)
                Text('Place of Birth: ${child['placeOfBirth']}'),
              if (child['gender'] != null) Text('Gender: ${child['gender']}'),
              if (child['address'] != null)
                Text('Address: ${child['address']}'),
              const SizedBox(height: 12),
            ],
            if (parents != null) ...[
              const Text(
                'Parents',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              if (parents['father'] != null)
                Text('Father: ${parents['father']}'),
              if (parents['mother'] != null)
                Text('Mother: ${parents['mother']}'),
              if (parents['marriageInfo'] != null)
                Text('Marriage Info: ${parents['marriageInfo']}'),
              const SizedBox(height: 12),
            ] else if (parentsText != null && parentsText.isNotEmpty) ...[
              const Text(
                'Name of the Parents',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(parentsText),
              const SizedBox(height: 12),
            ],
            if (godparents != null) ...[
              const Text(
                'Godparents',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              if (godparents['godfather1'] != null)
                Text('Godfather 1: ${godparents['godfather1']}'),
              if (godparents['godmother1'] != null)
                Text('Godmother 1: ${godparents['godmother1']}'),
              if (godparents['godfather2'] != null)
                Text('Godfather 2: ${godparents['godfather2']}'),
              if (godparents['godmother2'] != null)
                Text('Godmother 2: ${godparents['godmother2']}'),
              const SizedBox(height: 12),
            ],
            if (baptism != null) ...[
              const Text(
                'Baptism Details',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              if (baptism['date'] != null)
                Text('Date: ${fmtDate(baptism['date']?.toString())}'),
              if (baptism['time'] != null) Text('Time: ${baptism['time']}'),
              if (baptism['place'] != null) Text('Place: ${baptism['place']}'),
              if (baptism['minister'] != null)
                Text('Minister: ${baptism['minister']}'),
              const SizedBox(height: 12),
            ],
            if (metadata != null) ...[
              const Text(
                'Additional Information',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              if (metadata['remarks'] != null)
                Text('Remarks: ${metadata['remarks']}'),
              if (metadata['certificateIssued'] != null)
                Text('Certificate Issued: ${metadata['certificateIssued']}'),
              if (metadata['staffName'] != null)
                Text('Prepared By: ${metadata['staffName']}'),
            ],
          ],
        ),
      ),
    );
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static String _parentsAsText(dynamic value) {
    if (value is String) return value.trim();
    final map = _asMap(value);
    if (map == null) return '';
    final father = map['father']?.toString().trim() ?? '';
    final mother = map['mother']?.toString().trim() ?? '';
    if (father.isNotEmpty && mother.isNotEmpty) return '$father / $mother';
    return father.isNotEmpty ? father : mother;
  }

  Widget _buildFlatRegisterBaptismDetails(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    final isTemporary = data['status'] == 'temporary';
    final rows = <(String, String)>[
      ('Volume Number', ManualRegisterNotes.field(data, 'volNo')),
      ('Series Number', ManualRegisterNotes.field(data, 'seriesNo')),
      ('No.', ManualRegisterNotes.field(data, 'lineNo')),
      ('Name of Child', ManualRegisterNotes.field(data, 'nameOfChild')),
      (
        'Place & Date of Birth',
        ManualRegisterNotes.field(data, 'placeAndBirthDate'),
      ),
      (
        'Name of the Parents (Mother\'s Maiden Name)',
        _parentsAsText(data['parents']),
      ),
      ('Resident Of', ManualRegisterNotes.field(data, 'residentsOf')),
      ('Date of Baptism', ManualRegisterNotes.field(data, 'dateOfBaptism')),
      ('Minister', ManualRegisterNotes.field(data, 'minister')),
      ('Sponsor', ManualRegisterNotes.field(data, 'sponsors')),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Baptism Register',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
                if (isTemporary) ...[
                  const SizedBox(width: 8),
                  Chip(
                    label: const Text('Temporary'),
                    visualDensity: VisualDensity.compact,
                    backgroundColor:
                        Theme.of(context).colorScheme.tertiaryContainer,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            for (final row in rows)
              if (row.$2.isNotEmpty) ...[
                Text(
                  row.$1,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(row.$2, style: const TextStyle(fontSize: 15)),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }

  Widget _buildFlatRegisterMarriageDetails(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    final isTemporary = data['status'] == 'temporary';
    final entry = ManualRegisterNotes.marriageEntryFromMap(data);
    final headerRows = <(String, String)>[
      ('Volume Number', ManualRegisterNotes.field(data, 'volNo')),
      ('Series Number', ManualRegisterNotes.field(data, 'seriesNo')),
      ('No.', ManualRegisterNotes.field(data, 'lineNo')),
    ];
    final sharedRows = <(String, String)>[
      ('Date of Marriage', entry.dateOfMarriage),
      ('Minister', entry.minister),
      ('License Number', entry.licenseNumber),
      ('Observations', entry.observations),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Marriage Register',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
                if (isTemporary) ...[
                  const SizedBox(width: 8),
                  Chip(
                    label: const Text('Temporary'),
                    visualDensity: VisualDensity.compact,
                    backgroundColor:
                        Theme.of(context).colorScheme.tertiaryContainer,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            for (final row in headerRows)
              if (row.$2.isNotEmpty) _detailField(context, row.$1, row.$2),
            _partyRegisterSection(context, 'Man', entry.groom),
            _partyRegisterSection(context, 'Woman', entry.bride),
            const SizedBox(height: 8),
            Text(
              'Shared',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 6),
            for (final row in sharedRows)
              if (row.$2.isNotEmpty) _detailField(context, row.$1, row.$2),
          ],
        ),
      ),
    );
  }

  Widget _partyRegisterSection(
    BuildContext context,
    String label,
    MarriagePartyInfo party,
  ) {
    final rows = <(String, String)>[
      ('Contracting Party', party.name),
      ('Legal Status', party.legalStatus),
      ('Actual Address', party.actualAddress),
      ('Dates & Place of Birth', party.datesPlaceOfBirth),
      ('Dates & Place of Baptism', party.datesPlaceOfBaptism),
      ('Parents', party.parents),
      ('Sponsors of Marriage', party.sponsors),
    ];
    if (!party.hasData && rows.every((r) => r.$2.isEmpty)) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 6),
          for (final row in rows)
            if (row.$2.isNotEmpty) _detailField(context, row.$1, row.$2),
        ],
      ),
    );
  }

  Widget _detailField(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.7),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 15)),
        ],
      ),
    );
  }

  Widget _buildMarriageDetails(
    BuildContext context,
    Map<String, dynamic> data,
    DateFormat df,
  ) {
    if (ManualRegisterNotes.usesFlatMarriageRegisterLayout(data)) {
      return _buildFlatRegisterMarriageDetails(context, data);
    }

    final marriage = data['marriage'] as Map<String, dynamic>?;
    final groom = data['groom'] as Map<String, dynamic>?;
    final bride = data['bride'] as Map<String, dynamic>?;
    final witnesses = data['witnesses'] as Map<String, dynamic>?;
    final remarks = data['remarks'];
    final meta = data['meta'] as Map<String, dynamic>?;

    String val(dynamic v) => v == null ? '' : v.toString();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (marriage != null) ...[
              const Text(
                'Marriage Details',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              if (marriage['date'] != null)
                Text('Date: ${val(marriage['date'])}'),
              if (marriage['place'] != null)
                Text('Place: ${marriage['place']}'),
              if (marriage['officiant'] != null)
                Text('Officiant: ${marriage['officiant']}'),
              if (marriage['licenseNumber'] != null)
                Text('License No: ${marriage['licenseNumber']}'),
              const SizedBox(height: 12),
            ],
            if (groom != null) ...[
              const Text(
                'Groom Information',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              if (groom['fullName'] != null) Text('Name: ${groom['fullName']}'),
              if (groom['ageOrDob'] != null)
                Text('Age / DOB: ${groom['ageOrDob']}'),
              if (groom['civilStatus'] != null)
                Text('Civil Status: ${groom['civilStatus']}'),
              if (groom['religion'] != null)
                Text('Religion: ${groom['religion']}'),
              if (groom['address'] != null)
                Text('Address: ${groom['address']}'),
              if (groom['father'] != null) Text('Father: ${groom['father']}'),
              if (groom['mother'] != null) Text('Mother: ${groom['mother']}'),
              const SizedBox(height: 12),
            ],
            if (bride != null) ...[
              const Text(
                'Bride Information',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              if (bride['fullName'] != null) Text('Name: ${bride['fullName']}'),
              if (bride['ageOrDob'] != null)
                Text('Age / DOB: ${bride['ageOrDob']}'),
              if (bride['civilStatus'] != null)
                Text('Civil Status: ${bride['civilStatus']}'),
              if (bride['religion'] != null)
                Text('Religion: ${bride['religion']}'),
              if (bride['address'] != null)
                Text('Address: ${bride['address']}'),
              if (bride['father'] != null) Text('Father: ${bride['father']}'),
              if (bride['mother'] != null) Text('Mother: ${bride['mother']}'),
              const SizedBox(height: 12),
            ],
            if (witnesses != null) ...[
              const Text(
                'Witnesses',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              if (witnesses['witness1'] != null)
                Text('Witness 1: ${witnesses['witness1']}'),
              if (witnesses['witness2'] != null)
                Text('Witness 2: ${witnesses['witness2']}'),
              const SizedBox(height: 12),
            ],
            if (remarks != null) ...[
              const Text(
                'Remarks',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(val(remarks)),
              const SizedBox(height: 12),
            ],
            if (meta != null) ...[
              const Text(
                'Registry / Meta',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              if (meta['bookNo'] != null) Text('Book No: ${meta['bookNo']}'),
              if (meta['pageNo'] != null) Text('Page No: ${meta['pageNo']}'),
              if (meta['lineNo'] != null) Text('Line No: ${meta['lineNo']}'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmationDetails(
    BuildContext context,
    Map<String, dynamic> data,
    DateFormat df,
  ) {
    final confirmand = data['confirmand'] as Map<String, dynamic>?;
    final parents = data['parents'] as Map<String, dynamic>?;
    final sponsor = data['sponsor'] as Map<String, dynamic>?;
    final confirmation = data['confirmation'] as Map<String, dynamic>?;
    final remarks = data['remarks'];
    final meta = data['meta'] as Map<String, dynamic>?;

    String fmtDate(String? iso) {
      if (iso == null || iso.isEmpty) return '';
      final d = DateTime.tryParse(iso);
      if (d == null) return iso;
      return df.format(d);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (confirmand != null) ...[
              const Text(
                'Confirmand Information',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              if (confirmand['fullName'] != null)
                Text('Name: ${confirmand['fullName']}'),
              if (confirmand['dateOfBirth'] != null)
                Text(
                  'Date of Birth: ${fmtDate(confirmand['dateOfBirth']?.toString())}',
                ),
              if (confirmand['placeOfBirth'] != null)
                Text('Place of Birth: ${confirmand['placeOfBirth']}'),
              if (confirmand['address'] != null)
                Text('Address: ${confirmand['address']}'),
              const SizedBox(height: 12),
            ],
            if (parents != null) ...[
              const Text(
                'Parents',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              if (parents['father'] != null)
                Text('Father: ${parents['father']}'),
              if (parents['mother'] != null)
                Text('Mother: ${parents['mother']}'),
              const SizedBox(height: 12),
            ],
            if (sponsor != null) ...[
              const Text(
                'Sponsor',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              if (sponsor['fullName'] != null)
                Text('Name: ${sponsor['fullName']}'),
              if (sponsor['relationship'] != null)
                Text('Relationship: ${sponsor['relationship']}'),
              const SizedBox(height: 12),
            ],
            if (confirmation != null) ...[
              const Text(
                'Confirmation Details',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              if (confirmation['date'] != null)
                Text('Date: ${fmtDate(confirmation['date']?.toString())}'),
              if (confirmation['place'] != null)
                Text('Place: ${confirmation['place']}'),
              if (confirmation['officiant'] != null)
                Text('Officiant: ${confirmation['officiant']}'),
              const SizedBox(height: 12),
            ],
            if (remarks != null && remarks.toString().isNotEmpty) ...[
              const Text(
                'Remarks',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(remarks.toString()),
              const SizedBox(height: 12),
            ],
            if (meta != null) ...[
              const Text(
                'Registry / Meta',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              if (meta['bookNo'] != null) Text('Book No: ${meta['bookNo']}'),
              if (meta['pageNo'] != null) Text('Page No: ${meta['pageNo']}'),
              if (meta['lineNo'] != null) Text('Line No: ${meta['lineNo']}'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDeathDetails(
    BuildContext context,
    Map<String, dynamic> data,
    DateFormat df,
  ) {
    final deceased = data['deceased'] as Map<String, dynamic>?;
    final family = data['family'] as Map<String, dynamic>?;
    final representative = data['representative'] as Map<String, dynamic>?;
    final burial = data['burial'] as Map<String, dynamic>?;
    final remarks = data['remarks'];
    final meta = data['meta'] as Map<String, dynamic>?;

    String fmtDate(String? iso) {
      if (iso == null || iso.isEmpty) return '';
      final d = DateTime.tryParse(iso);
      if (d == null) return iso;
      return df.format(d);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (deceased != null) ...[
              const Text(
                'Deceased Information',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              if (deceased['fullName'] != null)
                Text('Name: ${deceased['fullName']}'),
              if (deceased['gender'] != null)
                Text('Gender: ${deceased['gender']}'),
              if (deceased['age'] != null) Text('Age: ${deceased['age']}'),
              if (deceased['dateOfBirth'] != null)
                Text(
                  'Date of Birth: ${fmtDate(deceased['dateOfBirth']?.toString())}',
                ),
              if (deceased['dateOfDeath'] != null)
                Text(
                  'Date of Death: ${fmtDate(deceased['dateOfDeath']?.toString())}',
                ),
              if (deceased['placeOfDeath'] != null)
                Text('Place of Death: ${deceased['placeOfDeath']}'),
              if (deceased['causeOfDeath'] != null)
                Text('Cause of Death: ${deceased['causeOfDeath']}'),
              if (deceased['civilStatus'] != null)
                Text('Civil Status: ${deceased['civilStatus']}'),
              if (deceased['address'] != null)
                Text('Address: ${deceased['address']}'),
              const SizedBox(height: 12),
            ],
            if (family != null) ...[
              const Text(
                'Family',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              if (family['father'] != null) Text('Father: ${family['father']}'),
              if (family['mother'] != null) Text('Mother: ${family['mother']}'),
              if (family['spouse'] != null) Text('Spouse: ${family['spouse']}'),
              const SizedBox(height: 12),
            ],
            if (representative != null) ...[
              const Text(
                'Representative',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              if (representative['name'] != null)
                Text('Name: ${representative['name']}'),
              if (representative['relationship'] != null)
                Text('Relationship: ${representative['relationship']}'),
              const SizedBox(height: 12),
            ],
            if (burial != null) ...[
              const Text(
                'Burial Details',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              if (burial['date'] != null)
                Text('Date of Burial: ${fmtDate(burial['date']?.toString())}'),
              if (burial['place'] != null)
                Text('Place of Burial: ${burial['place']}'),
              if (burial['officiant'] != null)
                Text('Officiant: ${burial['officiant']}'),
              const SizedBox(height: 12),
            ],
            if (remarks != null && remarks.toString().isNotEmpty) ...[
              const Text(
                'Remarks',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(remarks.toString()),
              const SizedBox(height: 12),
            ],
            if (meta != null) ...[
              const Text(
                'Registry / Meta',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              if (meta['bookNo'] != null) Text('Book No: ${meta['bookNo']}'),
              if (meta['pageNo'] != null) Text('Page No: ${meta['pageNo']}'),
              if (meta['lineNo'] != null) Text('Line No: ${meta['lineNo']}'),
            ],
          ],
        ),
      ),
    );
  }

  _AdditionalInfo _extractAdditionalInfo(
    ParishRecord rec,
    Map<String, dynamic>? data,
  ) {
    String? remarks;
    bool cert = false;
    String? staff;

    if (data != null) {
      switch (rec.type) {
        case RecordType.baptism:
          final meta = data['metadata'] as Map<String, dynamic>?;
          if (meta != null) {
            remarks = meta['remarks']?.toString();
            cert = meta['certificateIssued'] == true;
            staff = meta['staffName']?.toString();
          }
          break;
        case RecordType.marriage:
          remarks = data['remarks']?.toString();
          final meta = data['meta'] as Map<String, dynamic>?;
          if (meta != null) {
            cert = meta['certificateIssued'] == true;
            staff = meta['staffName']?.toString();
          }
          break;
        case RecordType.confirmation:
          remarks = data['remarks']?.toString();
          final meta = data['meta'] as Map<String, dynamic>?;
          if (meta != null) {
            cert = meta['certificateIssued'] == true;
            staff = meta['staffName']?.toString();
          }
          break;
        case RecordType.funeral:
          remarks = data['remarks']?.toString();
          final meta = data['meta'] as Map<String, dynamic>?;
          if (meta != null) {
            cert = meta['certificateIssued'] == true;
            staff = meta['staffName']?.toString();
          }
          break;
      }
    }

    return _AdditionalInfo(
      remarks: remarks,
      certificateIssued: cert,
      staffName: staff,
    );
  }
}

class _AdditionalInfo {
  final String? remarks;
  final bool certificateIssued;
  final String? staffName;

  const _AdditionalInfo({
    this.remarks,
    this.certificateIssued = false,
    this.staffName,
  });

  bool get hasAny =>
      (remarks != null && remarks!.isNotEmpty) ||
      certificateIssued ||
      (staffName != null && staffName!.isNotEmpty);
}

extension FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
