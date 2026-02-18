import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../../../models/record.dart';
import '../../../services/records_repository.dart';
import '../../../services/admin_repository.dart';

class AdminRecordsPage extends StatefulWidget {
  final Map<String, dynamic>? initialFilter;

  const AdminRecordsPage({super.key, this.initialFilter});

  @override
  State<AdminRecordsPage> createState() => _AdminRecordsPageState();
}

class _AdminRecordsPageState extends State<AdminRecordsPage> {
  final _searchCtrl = TextEditingController();
  String _selectedType = 'baptism';
  final bool _desc = true;
  final _uuid = const Uuid();
  DateTime? _from;
  DateTime? _to;
  final _repo = RecordsRepository();
  final _adminRepo = AdminRepository();
  StreamSubscription<List<ParishRecord>>? _sub;
  Timer? _timer;
  List<ParishRecord> _records = const [];

  @override
  void initState() {
    super.initState();
    final f = widget.initialFilter;
    if (f != null) {
      final type = f['type']?.toString();
      if (type != null && type.isNotEmpty) {
        _selectedType = type;
      }
      final fromStr = f['from']?.toString();
      final toStr = f['to']?.toString();
      if (fromStr != null && fromStr.isNotEmpty) {
        _from = DateTime.tryParse(fromStr);
      }
      if (toStr != null && toStr.isNotEmpty) {
        _to = DateTime.tryParse(toStr);
      }
    }

    _loadFromBackend();
    _timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _loadFromBackend(),
    );
  }

  Future<void> _openNewRecord() async {
    final type = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('New Record'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'baptism'),
            child: const Text('Baptism Record Entry'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'marriage'),
            child: const Text('Marriage Record Entry'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'confirmation'),
            child: const Text('Confirmation Record Entry'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(
              ctx,
              'funeral',
            ), // Changed from 'death' to 'funeral'
            child: const Text('Death / Burial Record Entry'),
          ),
        ],
      ),
    );
    if (!mounted || type == null) return;

    String? route;
    switch (type) {
      case 'baptism':
        route = '/admin/records/new/baptism';
        break;
      case 'marriage':
        route = '/admin/records/new/marriage';
        break;
      case 'confirmation':
        route = '/admin/records/new/confirmation';
        break;
      case 'funeral': // Changed from 'death' to 'funeral'
        route =
            '/admin/records/new/death'; // Keep route as 'death' if that's what your router expects
        break;
    }

    if (route != null) {
      final saved = await context.push(route);
      if (saved == true && mounted) {
        await _loadFromBackend();
      }
    }
  }

  Future<void> _loadFromBackend() async {
    try {
      // First try the main records repository
      final primary = await _repo.list();
      if (primary.isNotEmpty) {
        if (mounted) setState(() => _records = primary);
        developer.log(
          'Admin loaded ${primary.length} records',
          name: 'AdminRecordsPage',
        );
        return;
      }

      // If primary returned 0 records, also try the admin repo
      final fallback = await _adminRepo.listRecent(limit: 100, days: 365);
      if (mounted) setState(() => _records = fallback);
      developer.log(
        'Admin primary list returned 0, loaded ${fallback.length} records from admin repo',
        name: 'AdminRecordsPage',
      );
    } catch (e) {
      if (!mounted) return;
      developer.log('Admin records load failed: $e', name: 'AdminRecordsPage');
      // Try fallback with admin repo
      try {
        final list = await _adminRepo.listRecent(limit: 100, days: 365);
        if (mounted) setState(() => _records = list);
        developer.log(
          'Admin loaded ${list.length} records from admin repo',
          name: 'AdminRecordsPage',
        );
      } catch (e2) {
        developer.log(
          'Admin fallback also failed: $e2',
          name: 'AdminRecordsPage',
        );
      }
    }
  }

  void _openRecordForm(ParishRecord rec) {
    String route;
    switch (rec.type) {
      case RecordType.baptism:
        route = '/admin/records/new/baptism';
        break;
      case RecordType.marriage:
        route = '/admin/records/new/marriage';
        break;
      case RecordType.confirmation:
        route = '/admin/records/new/confirmation';
        break;
      case RecordType.funeral:
        route = '/admin/records/new/death';
        break;
    }

    context.push(route, extra: rec);
  }

  // Helper method to convert RecordType to string
  String _getRecordTypeString(RecordType type) {
    switch (type) {
      case RecordType.baptism:
        return 'baptism';
      case RecordType.marriage:
        return 'marriage';
      case RecordType.confirmation:
        return 'confirmation';
      case RecordType.funeral:
        return 'funeral';
    }
  }

  List<Map<String, dynamic>> _load() {
    // Transform backend records to the map structure the UI expects
    final items = _records.map((r) {
      final base = <String, dynamic>{
        'id': r.id,
        'name': r.name,
        'type': _getRecordTypeString(
          r.type,
        ), // Use helper method instead of .name
        'typeIndex': r.type.index,
        'date': r.date.toIso8601String(),
        'parish': r.parish,
        'notes': r.notes,
        'record': r,
      };

      final notesStr = r.notes;
      if (notesStr != null && notesStr.isNotEmpty) {
        try {
          final decoded = json.decode(notesStr) as Map<String, dynamic>;
          switch (r.type) {
            case RecordType.baptism:
              final registry =
                  (decoded['registry'] as Map<String, dynamic>?) ?? {};
              base['bookNo'] = registry['bookNo']?.toString();
              base['pageNo'] = registry['pageNo']?.toString();
              base['lineNo'] = registry['lineNo']?.toString();
              break;
            case RecordType.marriage:
              final groom = (decoded['groom'] as Map<String, dynamic>?) ?? {};
              final bride = (decoded['bride'] as Map<String, dynamic>?) ?? {};
              final meta = (decoded['meta'] as Map<String, dynamic>?) ?? {};
              base['groomName'] = groom['fullName']?.toString();
              base['brideName'] = bride['fullName']?.toString();
              base['bookNo'] = meta['bookNo']?.toString();
              base['pageNo'] = meta['pageNo']?.toString();
              base['lineNo'] = meta['lineNo']?.toString();
              break;
            case RecordType.confirmation:
              final confirmand =
                  (decoded['confirmand'] as Map<String, dynamic>?) ?? {};
              final sponsor =
                  (decoded['sponsor'] as Map<String, dynamic>?) ?? {};
              final meta = (decoded['meta'] as Map<String, dynamic>?) ?? {};
              base['confirmandName'] = confirmand['fullName']?.toString();
              base['sponsorName'] = sponsor['fullName']?.toString();
              base['bookNo'] = meta['bookNo']?.toString();
              base['pageNo'] = meta['pageNo']?.toString();
              base['lineNo'] = meta['lineNo']?.toString();
              break;
            case RecordType.funeral:
              final deceased =
                  (decoded['deceased'] as Map<String, dynamic>?) ?? {};
              final burial = (decoded['burial'] as Map<String, dynamic>?) ?? {};
              final meta = (decoded['meta'] as Map<String, dynamic>?) ?? {};
              base['deceasedName'] = deceased['fullName']?.toString() ?? r.name;
              base['dateOfDeath'] = deceased['dateOfDeath']?.toString();
              base['dateOfBurial'] = burial['date']?.toString();
              base['bookNo'] = meta['bookNo']?.toString();
              base['pageNo'] = meta['pageNo']?.toString();
              base['lineNo'] = meta['lineNo']?.toString();
              break;
          }
        } catch (_) {
          // Ignore JSON errors; fall back to base fields only
        }
      }

      return base;
    }).toList();
    // filter by type, parish, search, and date
    final q = _searchCtrl.text.trim().toLowerCase();
    Iterable<Map<String, dynamic>> it = items;
    if (_selectedType.isNotEmpty) {
      it = it.where((m) => (m['type'] ?? '').toString() == _selectedType);
    }
    if (q.isNotEmpty) {
      it = it.where(
        (m) => m.values.any(
          (val) => val?.toString().toLowerCase().contains(q) ?? false,
        ),
      );
    }
    // date range inclusive
    if (_from != null || _to != null) {
      it = it.where((m) {
        final s = (m['date'] ?? '').toString();
        final d = DateTime.tryParse(s);
        if (d == null) return false;
        if (_from != null &&
            d.isBefore(DateTime(_from!.year, _from!.month, _from!.day))) {
          return false;
        }
        if (_to != null &&
            d.isAfter(DateTime(_to!.year, _to!.month, _to!.day, 23, 59, 59))) {
          return false;
        }
        return true;
      });
    }
    final list = it.toList();
    // sort by date desc/asc
    list.sort((a, b) {
      final ad = ((a['date'] ?? '')).toString();
      final bd = ((b['date'] ?? '')).toString();
      final cmp = ad.compareTo(bd);
      return _desc ? -cmp : cmp;
    });
    return list;
  }

  Future<void> _upsert({Map<String, dynamic>? existing}) async {
    final firstCtrl = TextEditingController(
      text: existing?['firstName']?.toString() ?? '',
    );
    final lastCtrl = TextEditingController(
      text: existing?['lastName']?.toString() ?? '',
    );
    final parishCtrl = TextEditingController(
      text: existing?['parish']?.toString() ?? '',
    );
    final notesCtrl = TextEditingController(
      text: existing?['notes']?.toString() ?? '',
    );
    final nameFallback = existing?['name']?.toString() ?? '';
    String type = existing?['type']?.toString() ?? 'baptism';
    DateTime date = () {
      final raw = existing?['date']?.toString();
      if (raw == null || raw.isEmpty) return DateTime.now();
      return DateTime.tryParse(raw) ?? DateTime.now();
    }();

    String? error;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) {
          return AlertDialog(
            title: Text(existing == null ? 'Add Record' : 'Edit Record'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: firstCtrl,
                          decoration: InputDecoration(
                            labelText: 'First name',
                            errorText: error,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: lastCtrl,
                          decoration: InputDecoration(
                            labelText: 'Last name',
                            errorText: error,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: const [
                      DropdownMenuItem(
                        value: 'baptism',
                        child: Text('Baptism'),
                      ),
                      DropdownMenuItem(
                        value: 'marriage',
                        child: Text('Marriage'),
                      ),
                      DropdownMenuItem(
                        value: 'funeral',
                        child: Text('Funeral'),
                      ),
                      DropdownMenuItem(
                        value: 'confirmation',
                        child: Text('Confirmation'),
                      ),
                    ],
                    onChanged: (v) => setStateDialog(() => type = v ?? type),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Date: ${date.toLocal().toString().split(' ').first}',
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: date,
                            firstDate: DateTime(1900),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setStateDialog(() => date = picked);
                          }
                        },
                        child: const Text('Pick date'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: parishCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Parish (optional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtrl,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final f = firstCtrl.text.trim();
                  final l = lastCtrl.text.trim();
                  if (f.isEmpty && l.isEmpty && nameFallback.isEmpty) {
                    setStateDialog(() => error = 'Enter first or last name');
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    if (saved == true) {
      final id = existing?['id']?.toString() ?? _uuid.v4();
      final f = firstCtrl.text.trim();
      final l = lastCtrl.text.trim();
      final fullName = (f.isEmpty && l.isEmpty)
          ? nameFallback
          : [f, l].where((x) => x.isNotEmpty).join(' ');
      if (existing == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Add via admin not supported yet')),
          );
        }
      } else {
        await _adminRepo.update(
          id,
          name: fullName,
          parish: parishCtrl.text.trim().isEmpty
              ? null
              : parishCtrl.text.trim(),
        );
      }
      if (mounted) setState(() {});
    }
  }

  Future<void> _delete(String key) async {
    try {
      await _repo.delete(key);
    } catch (_) {
      await _adminRepo.delete(key);
    }
    if (mounted) {
      await _loadFromBackend();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _sub?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _load();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Records Management',
                          style: theme.textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _selectedType.isEmpty
                              ? '${items.length} records'
                              : '${items.length} ${_formatTypeLabel(_selectedType).toLowerCase()} records',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.7,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  FilledButton.icon(
                    onPressed: _openNewRecord,
                    icon: const Icon(Icons.add),
                    label: const Text('Add record'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 720;
                  final searchWidth = isNarrow ? constraints.maxWidth : 320.0;
                  return Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      SizedBox(
                        width: searchWidth,
                        child: TextField(
                          controller: _searchCtrl,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText: 'Search records',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      SizedBox(
                        width: 200,
                        child: DropdownButtonFormField<String>(
                          initialValue: _selectedType,
                          decoration: const InputDecoration(
                            labelText: 'Record type',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'baptism',
                              child: Text('Baptism'),
                            ),
                            DropdownMenuItem(
                              value: 'marriage',
                              child: Text('Marriage'),
                            ),
                            DropdownMenuItem(
                              value: 'confirmation',
                              child: Text('Confirmation'),
                            ),
                            DropdownMenuItem(
                              value: 'funeral',
                              child: Text('Death / Burial'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => _selectedType = v);
                          },
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _from ?? DateTime.now(),
                            firstDate: DateTime(1900),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setState(() {
                              _from = DateTime(
                                picked.year,
                                picked.month,
                                picked.day,
                              );
                            });
                          }
                        },
                        icon: const Icon(Icons.calendar_today),
                        label: Text(
                          _from == null
                              ? 'From date'
                              : 'From: ${DateFormat.yMMMd().format(_from!)}',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _to ?? _from ?? DateTime.now(),
                            firstDate: DateTime(1900),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setState(() {
                              _to = DateTime(
                                picked.year,
                                picked.month,
                                picked.day,
                              );
                            });
                          }
                        },
                        icon: const Icon(Icons.calendar_month),
                        label: Text(
                          _to == null
                              ? 'To date'
                              : 'To: ${DateFormat.yMMMd().format(_to!)}',
                        ),
                      ),
                      IconButton(
                        tooltip: 'Clear date filter',
                        onPressed: () {
                          if (_from == null && _to == null) return;
                          setState(() {
                            _from = null;
                            _to = null;
                          });
                        },
                        icon: const Icon(Icons.clear),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              const Divider(height: 0),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (items.isEmpty) {
                      return _buildEmptyState(context);
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildRecordsHeader(context, items.length),
                        const Divider(height: 0),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(12),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                columns: const [
                                  DataColumn(label: Text('Name')),
                                  DataColumn(label: Text('Type')),
                                  DataColumn(label: Text('Date')),
                                  DataColumn(label: Text('Parish')),
                                  DataColumn(label: Text('Actions')),
                                ],
                                rows: items.map((m) {
                                  final key = m['id']?.toString() ?? '';
                                  final type = (m['type'] ?? '').toString();
                                  final typeLabel = _formatTypeLabel(type);
                                  final rawParish = (m['parish'] ?? '')
                                      .toString();
                                  final parish = rawParish.isEmpty
                                      ? 'Holy Rosary Parish – Oroquieta City'
                                      : rawParish;
                                  final dateRaw = (m['date'] ?? '').toString();
                                  DateTime? d = DateTime.tryParse(
                                    dateRaw.isEmpty ? '' : dateRaw,
                                  );
                                  final df = DateFormat.yMMMd();
                                  final dateLabel = d == null
                                      ? ''
                                      : df.format(d.toLocal());
                                  final name = (m['name'] ?? 'Untitled')
                                      .toString();
                                  final rec = m['record'] as ParishRecord?;

                                  final cells = <DataCell>[
                                    DataCell(
                                      Text(
                                        name,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    DataCell(
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _typeColor(
                                            context,
                                            type,
                                          ).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          typeLabel,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: _typeColor(
                                                  context,
                                                  type,
                                                ),
                                                fontWeight: FontWeight.w500,
                                              ),
                                        ),
                                      ),
                                    ),
                                    DataCell(Text(dateLabel)),
                                    DataCell(Text(parish)),
                                  ];

                                  cells.add(
                                    DataCell(
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            tooltip: 'Edit',
                                            onPressed: () {
                                              final recLocal =
                                                  m['record'] as ParishRecord?;
                                              if (recLocal == null) {
                                                _upsert(existing: m);
                                                return;
                                              }

                                              _openRecordForm(recLocal);
                                            },
                                            icon: const Icon(
                                              Icons.edit_outlined,
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Delete',
                                            onPressed: key.isEmpty
                                                ? null
                                                : () async {
                                                    final ok = await showDialog<bool>(
                                                      context: context,
                                                      builder: (ctx) => AlertDialog(
                                                        title: const Text(
                                                          'Delete record?',
                                                        ),
                                                        content: Text(
                                                          'Are you sure you want to delete "$key"?',
                                                        ),
                                                        actions: [
                                                          TextButton(
                                                            onPressed: () =>
                                                                Navigator.pop(
                                                                  ctx,
                                                                  false,
                                                                ),
                                                            child: const Text(
                                                              'Cancel',
                                                            ),
                                                          ),
                                                          FilledButton(
                                                            onPressed: () =>
                                                                Navigator.pop(
                                                                  ctx,
                                                                  true,
                                                                ),
                                                            child: const Text(
                                                              'Delete',
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    );
                                                    if (ok == true) {
                                                      await _delete(key);
                                                    }
                                                  },
                                            icon: const Icon(
                                              Icons.delete_outline,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );

                                  return DataRow(
                                    cells: cells,
                                    onSelectChanged: (selected) {
                                      if (selected != true) return;
                                      if (rec == null) return;
                                      context.push('/admin/records/${rec.id}');
                                    },
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecordsHeader(BuildContext context, int count) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Records',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count total',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.folder_off_outlined,
            size: 48,
            color: colorScheme.onSurface.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text('No records found', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Try adjusting filters or add a new record to get started.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _openNewRecord,
            icon: const Icon(Icons.add),
            label: const Text('Add first record'),
          ),
        ],
      ),
    );
  }

  String _formatTypeLabel(String type) {
    switch (type) {
      case 'baptism':
        return 'Baptism';
      case 'marriage':
        return 'Marriage';
      case 'confirmation':
        return 'Confirmation';
      case 'funeral':
        return 'Death / Burial';
      default:
        return type.isEmpty ? 'Unknown' : type;
    }
  }

  Color _typeColor(BuildContext context, String type) {
    switch (type) {
      case 'baptism':
        return Colors.blue;
      case 'marriage':
        return Colors.pink;
      case 'confirmation':
        return Colors.purple;
      case 'funeral':
        return Colors.grey;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }
}
