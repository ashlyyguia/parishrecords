// ignore_for_file: use_build_context_synchronously

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import '../../../providers/household_provider.dart';

/// User OCR Sacrament Linking Screen - scans and extracts sacramental data
class UserOcrSacramentLinkScreen extends ConsumerStatefulWidget {
  final String householdId;
  final String? memberId;

  const UserOcrSacramentLinkScreen({
    super.key,
    required this.householdId,
    this.memberId,
  });

  @override
  ConsumerState<UserOcrSacramentLinkScreen> createState() => _UserOcrSacramentLinkScreenState();
}

class _UserOcrSacramentLinkScreenState extends ConsumerState<UserOcrSacramentLinkScreen> {
  File? _imageFile;
  bool _isProcessing = false;
  String _extractedText = '';
  Map<String, dynamic> _extractedData = {};
  final ImagePicker _picker = ImagePicker();
  final TextRecognizer _textRecognizer = TextRecognizer();

  @override
  void dispose() {
    _textRecognizer.close();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1800,
        maxHeight: 1800,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        setState(() {
          _imageFile = File(pickedFile.path);
          _extractedText = '';
          _extractedData = {};
        });
        await _processOcr();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  Future<void> _processOcr() async {
    if (_imageFile == null) return;

    setState(() => _isProcessing = true);

    try {
      final inputImage = InputImage.fromFile(_imageFile!);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      _extractedText = recognizedText.text;
      _extractedData = _parseExtractedText(_extractedText);

      setState(() => _isProcessing = false);
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error processing image: $e')),
        );
      }
    }
  }

  Map<String, dynamic> _parseExtractedText(String text) {
    final data = <String, dynamic>{};
    final lines = text.split('\n');

    // Try to extract sacrament type
    final sacramentKeywords = {
      'baptism': ['baptism', 'baptized', 'baptismal'],
      'confirmation': ['confirmation', 'confirmed'],
      'marriage': ['marriage', 'married', 'matrimony'],
      'death': ['death', 'died', 'burial', 'funeral'],
      'communion': ['communion', 'eucharist', 'first communion'],
    };

    for (final line in lines) {
      final lowerLine = line.toLowerCase();
      
      // Check for sacrament type
      for (final entry in sacramentKeywords.entries) {
        for (final keyword in entry.value) {
          if (lowerLine.contains(keyword)) {
            data['sacramentType'] = entry.key;
            break;
          }
        }
      }

      // Try to extract name (usually preceded by "Name:" or similar)
      if (lowerLine.contains('name:') || lowerLine.contains('name of')) {
        final nameMatch = RegExp(r'name[:\s]+([A-Za-z\s\.]+)', caseSensitive: false).firstMatch(line);
        if (nameMatch != null) {
          data['name'] = nameMatch.group(1)?.trim();
        }
      }

      // Try to extract date (various formats)
      final datePatterns = [
        RegExp(r'(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})'),
        RegExp(r'(\d{1,2})\s+(January|February|March|April|May|June|July|August|September|October|November|December)[,\s]+(\d{2,4})', caseSensitive: false),
      ];

      for (final pattern in datePatterns) {
        final match = pattern.firstMatch(line);
        if (match != null) {
          data['date'] = match.group(0);
          break;
        }
      }

      // Try to extract parish/church name
      if (lowerLine.contains('parish') || lowerLine.contains('church')) {
        data['parish'] = line.trim();
      }
    }

    return data;
  }

  Future<void> _linkSacramentToMember() async {
    if (_extractedData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No data to link')),
      );
      return;
    }

    // If memberId is provided, link directly
    if (widget.memberId != null) {
      await _confirmAndLink(widget.memberId!);
      return;
    }

    // Otherwise show member selection dialog
    _showMemberSelectionDialog();
  }

  void _showMemberSelectionDialog() async {
    final members = await ref.read(householdRepositoryProvider).getHouseholdMembers(widget.householdId);
    
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Member'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: members.length,
            itemBuilder: (context, index) {
              final member = members[index];
              return ListTile(
                leading: CircleAvatar(
                  child: Text(member.fullName.isNotEmpty ? member.fullName[0] : '?'),
                ),
                title: Text(member.fullName),
                subtitle: Text(member.role),
                onTap: () {
                  Navigator.pop(context);
                  _confirmAndLink(member.id);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAndLink(String memberId) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Link'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Link this sacrament record to the selected member?'),
            const SizedBox(height: 16),
            if (_extractedData['sacramentType'] != null)
              _buildDataRow('Type:', _extractedData['sacramentType']!.toString().toUpperCase()),
            if (_extractedData['name'] != null)
              _buildDataRow('Name:', _extractedData['name']!),
            if (_extractedData['date'] != null)
              _buildDataRow('Date:', _extractedData['date']!),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm & Link'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Create sacrament record in the database
      await ref.read(householdRepositoryProvider).linkSacramentRecord(
        memberId: memberId,
        // Additional data would be saved here
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sacrament record linked successfully')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error linking record: $e')),
        );
      }
    }
  }

  Widget _buildDataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Scan Sacrament Record'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Instructions Card
            Card(
              elevation: 0,
              color: colorScheme.primaryContainer.withValues(alpha: 0.3),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Take a clear photo of the sacramental certificate or church record. The app will automatically extract the information.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Image Selection Buttons
            if (_imageFile == null) ...[
              Row(
                children: [
                  Expanded(
                    child: _ImageSourceButton(
                      icon: Icons.camera_alt_outlined,
                      label: 'Camera',
                      onTap: () => _pickImage(ImageSource.camera),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _ImageSourceButton(
                      icon: Icons.photo_library_outlined,
                      label: 'Gallery',
                      onTap: () => _pickImage(ImageSource.gallery),
                    ),
                  ),
                ],
              ),
            ] else ...[
              // Image Preview
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  _imageFile!,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              
              const SizedBox(height: 12),
              
              // Change Image Button
              Center(
                child: TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _imageFile = null;
                      _extractedText = '';
                      _extractedData = {};
                    });
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Choose Different Image'),
                ),
              ),
            ],
            
            const SizedBox(height: 24),
            
            // Processing Indicator
            if (_isProcessing) ...[
              Center(
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      'Extracting text from image...',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
            // Extracted Data Card
            if (!_isProcessing && _extractedData.isNotEmpty) ...[
              Text(
                'Extracted Information',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_extractedData['sacramentType'] != null)
                        _buildEditableField(
                          'Sacrament Type',
                          _extractedData['sacramentType']!.toString().toUpperCase(),
                          Icons.church_outlined,
                          Colors.purple,
                          (val) => _extractedData['sacramentType'] = val,
                        ),
                      if (_extractedData['name'] != null)
                        _buildEditableField(
                          'Name',
                          _extractedData['name']!,
                          Icons.person_outline,
                          Colors.blue,
                          (val) => _extractedData['name'] = val,
                        ),
                      if (_extractedData['date'] != null)
                        _buildEditableField(
                          'Date',
                          _extractedData['date']!,
                          Icons.calendar_today_outlined,
                          Colors.orange,
                          (val) => _extractedData['date'] = val,
                        ),
                      if (_extractedData['parish'] != null)
                        _buildEditableField(
                          'Parish',
                          _extractedData['parish']!,
                          Icons.location_on_outlined,
                          Colors.green,
                          (val) => _extractedData['parish'] = val,
                        ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Link Button
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _linkSacramentToMember,
                  icon: const Icon(Icons.link),
                  label: Text(widget.memberId != null 
                    ? 'Link to Member' 
                    : 'Select Member & Link'),
                ),
              ),
            ],
            
            // Raw Text (for debugging)
            if (_extractedText.isNotEmpty && !_isProcessing) ...[
              const SizedBox(height: 24),
              ExpansionTile(
                title: const Text('View Raw Extracted Text'),
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _extractedText,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEditableField(String label, String value, IconData icon, Color color, Function(String) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              initialValue: value,
              decoration: InputDecoration(
                labelText: label,
                labelStyle: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// Image Source Button Widget
class _ImageSourceButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ImageSourceButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
