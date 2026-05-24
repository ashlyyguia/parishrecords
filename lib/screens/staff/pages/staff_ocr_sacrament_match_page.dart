// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../../../models/household.dart';
import '../../../providers/household_provider.dart';
import '../../../widgets/app_loading.dart';

/// Screen for OCR-based sacrament record matching to household members
class StaffOcrSacramentMatchPage extends ConsumerStatefulWidget {
  final String householdId;

  const StaffOcrSacramentMatchPage({super.key, required this.householdId});

  @override
  ConsumerState<StaffOcrSacramentMatchPage> createState() =>
      _StaffOcrSacramentMatchPageState();
}

class _StaffOcrSacramentMatchPageState
    extends ConsumerState<StaffOcrSacramentMatchPage> {
  File? _selectedImage;
  bool _isProcessing = false;
  String _extractedText = '';
  List<OcrExtractedData> _extractedData = [];
  String? _selectedSacramentType;

  final _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  @override
  void dispose() {
    _textRecognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final householdAsync = ref.watch(householdProvider(widget.householdId));
    final membersAsync = ref.watch(
      householdMembersStreamProvider(widget.householdId),
    );

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('OCR Sacrament Matching'),
        actions: [
          if (_extractedData.isNotEmpty)
            TextButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.refresh),
              label: const Text('New Scan'),
            ),
        ],
      ),
      body: householdAsync.when(
        data: (household) {
          if (household == null) {
            return const Center(child: Text('Household not found'));
          }

          return membersAsync.when(
            data: (members) => _buildContent(context, household, members),
            loading: () => const AppLoading(message: 'Loading members...'),
            error: (e, _) => Center(child: Text('Error: $e')),
          );
        },
        loading: () => const AppLoading(message: 'Loading household...'),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    Household household,
    List<HouseholdMember> members,
  ) {
    final theme = Theme.of(context);

    if (_selectedImage == null) {
      return _buildImageSelectionView(theme);
    }

    if (_isProcessing) {
      return _buildProcessingView();
    }

    if (_extractedData.isEmpty) {
      return _buildExtractedTextView();
    }

    return _buildMatchingView(context, household, members);
  }

  Widget _buildImageSelectionView(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.document_scanner_outlined,
              size: 80,
              color: theme.colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'Scan Sacramental Register',
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Take a photo or upload an image of a sacramental record to automatically extract information and match it to household members.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Camera'),
                ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  onPressed: () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Gallery'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Sacrament Type Selection
            SegmentedButton<String?>(
              segments: const [
                ButtonSegment(
                  value: 'baptism',
                  label: Text('Baptism'),
                  icon: Icon(Icons.water),
                ),
                ButtonSegment(
                  value: 'confirmation',
                  label: Text('Confirmation'),
                  icon: Icon(Icons.church),
                ),
                ButtonSegment(
                  value: 'marriage',
                  label: Text('Marriage'),
                  icon: Icon(Icons.favorite),
                ),
              ],
              selected: {_selectedSacramentType},
              onSelectionChanged: (v) =>
                  setState(() => _selectedSacramentType = v.first),
              emptySelectionAllowed: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProcessingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 80,
            height: 80,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 24),
          Text(
            'Processing Image...',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Extracting text using ML Kit OCR',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildExtractedTextView() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Extracted Text',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              FilledButton.icon(
                onPressed: _processText,
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('Parse Data'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: TextFormField(
                  initialValue: _extractedText,
                  maxLines: null,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Review and edit raw extracted text here before parsing...',
                  ),
                  onChanged: (val) => _extractedText = val,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMatchingView(
    BuildContext context,
    Household household,
    List<HouseholdMember> members,
  ) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Review & Match to Members',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Verify the extracted data and match it to the correct household member.',
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: _extractedData.length,
              itemBuilder: (context, index) {
                final data = _extractedData[index];
                return _ExtractedDataCard(
                  data: data,
                  householdMembers: members,
                  onMatch: (member) => _linkToMember(data, member),
                  onCreateNew: () => _createNewMember(data),
                  onEdit: () => _editExtractedData(data),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 85,
    );

    if (picked != null) {
      setState(() {
        _selectedImage = File(picked.path);
      });
      await _processOcr();
    }
  }

  Future<void> _processOcr() async {
    if (_selectedImage == null) return;

    setState(() => _isProcessing = true);

    try {
      final inputImage = InputImage.fromFile(_selectedImage!);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      setState(() {
        _extractedText = recognizedText.text;
        _isProcessing = false;
      });
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('OCR Error: $e')));
      }
    }
  }

  void _processText() {
    // Parse the extracted text into structured data
    final data = _parseSacramentText(_extractedText);
    setState(() => _extractedData = data);
  }

  List<OcrExtractedData> _parseSacramentText(String text) {
    final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
    final results = <OcrExtractedData>[];

    // Simple parsing logic - this can be enhanced with ML/NLP
    String? currentName;
    String? currentDate;
    String? currentSacrament;

    for (final line in lines) {
      final lower = line.toLowerCase();

      // Detect sacrament type
      if (lower.contains('baptism') || lower.contains('bautismo')) {
        currentSacrament = 'baptism';
      } else if (lower.contains('confirmation') || lower.contains('kumpil')) {
        currentSacrament = 'confirmation';
      } else if (lower.contains('marriage') || lower.contains('kasal')) {
        currentSacrament = 'marriage';
      } else if (lower.contains('death') || lower.contains('death')) {
        currentSacrament = 'death';
      }

      // Try to extract name (simple heuristic)
      if (line.length > 3 &&
          !lower.contains('date') &&
          !lower.contains('page') &&
          !lower.contains('register') &&
          !lower.contains('sacrament')) {
        currentName = line.trim();
      }

      // Try to extract date
      final dateMatch = RegExp(
        r'(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})',
      ).firstMatch(line);
      if (dateMatch != null) {
        currentDate = line.trim();
      }

      // If we have a name, create an entry
      if (currentName != null && currentName.length > 5) {
        results.add(
          OcrExtractedData(
            name: currentName,
            sacramentType:
                currentSacrament ?? _selectedSacramentType ?? 'unknown',
            date: currentDate,
            rawText: line,
            confidence: 0.8,
          ),
        );
        currentName = null;
      }
    }

    return results.isEmpty
        ? [
            OcrExtractedData(
              name: 'Unknown',
              sacramentType: _selectedSacramentType ?? 'unknown',
              date: null,
              rawText: text.substring(0, text.length > 200 ? 200 : text.length),
              confidence: 0.5,
            ),
          ]
        : results;
  }

  void _reset() {
    setState(() {
      _selectedImage = null;
      _extractedText = '';
      _extractedData = [];
    });
  }

  Future<void> _linkToMember(
    OcrExtractedData data,
    HouseholdMember member,
  ) async {
    // Link the extracted sacrament data to a household member
    final notifier = ref.read(householdOperationsProvider.notifier);

    String? baptismId, confirmationId, marriageId, deathId;

    switch (data.sacramentType) {
      case 'baptism':
        baptismId = 'ocr_${DateTime.now().millisecondsSinceEpoch}';
      case 'confirmation':
        confirmationId = 'ocr_${DateTime.now().millisecondsSinceEpoch}';
      case 'marriage':
        marriageId = 'ocr_${DateTime.now().millisecondsSinceEpoch}';
      case 'death':
        deathId = 'ocr_${DateTime.now().millisecondsSinceEpoch}';
    }

    final updated = member.copyWith(
      baptismRecordId: baptismId ?? member.baptismRecordId,
      confirmationRecordId: confirmationId ?? member.confirmationRecordId,
      marriageRecordId: marriageId ?? member.marriageRecordId,
      deathRecordId: deathId ?? member.deathRecordId,
    );

    final success = await notifier.updateMember(updated);

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Linked ${data.sacramentType} to ${member.fullName}'),
        ),
      );

      // Remove from list
      setState(() {
        _extractedData.remove(data);
      });
    }
  }

  Future<void> _createNewMember(OcrExtractedData data) async {
    // Show dialog to create new member from extracted data
    final result = await showDialog<HouseholdMember>(
      context: context,
      builder: (context) => _CreateMemberFromOcrDialog(
        householdId: widget.householdId,
        extractedData: data,
      ),
    );

    if (result != null) {
      final notifier = ref.read(householdOperationsProvider.notifier);
      final created = await notifier.addMember(result);

      if (created != null && mounted) {
        // Now link the sacrament
        await _linkToMember(data, created);
      }
    }
  }

  void _editExtractedData(OcrExtractedData data) {
    // Show dialog to edit the extracted data
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Extracted Data'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: TextEditingController(text: data.name),
              decoration: const InputDecoration(labelText: 'Name'),
              onChanged: (v) => data.name = v,
            ),
            TextField(
              controller: TextEditingController(text: data.date ?? ''),
              decoration: const InputDecoration(labelText: 'Date'),
              onChanged: (v) => data.date = v,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {});
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

/// Data class for OCR extracted information
class OcrExtractedData {
  String name;
  String sacramentType;
  String? date;
  String rawText;
  double confidence;

  OcrExtractedData({
    required this.name,
    required this.sacramentType,
    this.date,
    required this.rawText,
    required this.confidence,
  });
}

/// Card for displaying extracted OCR data with matching options
class _ExtractedDataCard extends StatelessWidget {
  final OcrExtractedData data;
  final List<HouseholdMember> householdMembers;
  final Function(HouseholdMember) onMatch;
  final VoidCallback onCreateNew;
  final VoidCallback onEdit;

  const _ExtractedDataCard({
    required this.data,
    required this.householdMembers,
    required this.onMatch,
    required this.onCreateNew,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Find potential matches
    final matches = _findPotentialMatches(data.name, householdMembers);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getSacramentIcon(data.sacramentType),
                  color: _getSacramentColor(data.sacramentType),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    data.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: onEdit,
                  tooltip: 'Edit',
                ),
              ],
            ),
            if (data.date != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Date: ${data.date}',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Confidence: ${(data.confidence * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 12,
                color: data.confidence > 0.8 ? Colors.green : Colors.orange,
              ),
            ),
            const Divider(height: 24),
            Text(
              'Match to Household Member:',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            if (matches.isNotEmpty)
              ...matches.map(
                (member) => ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 16,
                    child: Text(member.initials),
                  ),
                  title: Text(member.fullName),
                  subtitle: Text(member.role),
                  trailing: FilledButton(
                    onPressed: () => onMatch(member),
                    child: const Text('Match'),
                  ),
                ),
              )
            else
              Text(
                'No matches found',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onCreateNew,
              icon: const Icon(Icons.person_add),
              label: const Text('Create New Member'),
            ),
          ],
        ),
      ),
    );
  }

  List<HouseholdMember> _findPotentialMatches(
    String name,
    List<HouseholdMember> members,
  ) {
    final lowerName = name.toLowerCase();
    return members.where((m) {
      final fullName = m.fullName.toLowerCase();
      // Simple string matching - can be enhanced with fuzzy matching
      return fullName.contains(lowerName) ||
          lowerName.contains(fullName) ||
          _similarity(fullName, lowerName) > 0.6;
    }).toList();
  }

  double _similarity(String s1, String s2) {
    // Simple Jaccard similarity for strings
    final set1 = s1.split('').toSet();
    final set2 = s2.split('').toSet();
    final intersection = set1.intersection(set2).length;
    final union = set1.union(set2).length;
    return union == 0 ? 0 : intersection / union;
  }

  IconData _getSacramentIcon(String type) {
    switch (type) {
      case 'baptism':
        return Icons.water;
      case 'confirmation':
        return Icons.church;
      case 'marriage':
        return Icons.favorite;
      case 'death':
        return Icons.sentiment_very_dissatisfied;
      default:
        return Icons.help;
    }
  }

  Color _getSacramentColor(String type) {
    switch (type) {
      case 'baptism':
        return Colors.cyan;
      case 'confirmation':
        return Colors.purple;
      case 'marriage':
        return Colors.pink;
      case 'death':
        return Colors.grey;
      default:
        return Colors.blue;
    }
  }
}

/// Dialog for creating a new member from OCR data
class _CreateMemberFromOcrDialog extends StatefulWidget {
  final String householdId;
  final OcrExtractedData extractedData;

  const _CreateMemberFromOcrDialog({
    required this.householdId,
    required this.extractedData,
  });

  @override
  State<_CreateMemberFromOcrDialog> createState() =>
      _CreateMemberFromOcrDialogState();
}

class _CreateMemberFromOcrDialogState
    extends State<_CreateMemberFromOcrDialog> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  String _role = 'Child';
  String _gender = 'Male';

  @override
  void initState() {
    super.initState();
    // Try to parse name from extracted data
    final nameParts = widget.extractedData.name.split(' ');
    if (nameParts.isNotEmpty) {
      _firstNameCtrl.text = nameParts.first;
      if (nameParts.length > 1) {
        _lastNameCtrl.text = nameParts.last;
      }
    }
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create New Member'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _firstNameCtrl,
                decoration: const InputDecoration(labelText: 'First Name *'),
                validator: (v) => v?.trim().isEmpty == true ? 'Required' : null,
              ),
              TextFormField(
                controller: _lastNameCtrl,
                decoration: const InputDecoration(labelText: 'Last Name *'),
                validator: (v) => v?.trim().isEmpty == true ? 'Required' : null,
              ),
              DropdownButtonFormField<String>(
                value: _role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: FamilyRoles.all
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (v) => setState(() => _role = v!),
              ),
              DropdownButtonFormField<String>(
                value: _gender,
                decoration: const InputDecoration(labelText: 'Gender'),
                items: Genders.all
                    .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                    .toList(),
                onChanged: (v) => setState(() => _gender = v!),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Create')),
      ],
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final member = HouseholdMember(
      id: '',
      householdId: widget.householdId,
      firstName: _firstNameCtrl.text.trim(),
      lastName: _lastNameCtrl.text.trim(),
      fullName: '${_firstNameCtrl.text.trim()} ${_lastNameCtrl.text.trim()}',
      role: _role,
      gender: _gender,
      civilStatus: 'Single',
    );

    Navigator.pop(context, member);
  }
}
