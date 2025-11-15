import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/record.dart';
import '../../providers/records_provider.dart';

enum CertificateRequestStatus { pending, processing, released }

class CertificateRequestFormScreen extends ConsumerStatefulWidget {
  const CertificateRequestFormScreen({super.key});

  @override
  ConsumerState<CertificateRequestFormScreen> createState() => _CertificateRequestFormScreenState();
}

class _CertificateRequestFormScreenState extends ConsumerState<CertificateRequestFormScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // Request details
  String _recordType = 'Baptism';
  final _fullNameCtrl = TextEditingController();
  DateTime? _eventDate;
  final _eventPlaceCtrl = TextEditingController();
  String _purpose = 'School';
  
  // Requester information
  final _requesterNameCtrl = TextEditingController();
  final _contactInfoCtrl = TextEditingController();
  DateTime? _preferredPickupDate;
  final _remarksCtrl = TextEditingController();
  
  final CertificateRequestStatus _status = CertificateRequestStatus.pending;

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _eventPlaceCtrl.dispose();
    _requesterNameCtrl.dispose();
    _contactInfoCtrl.dispose();
    _remarksCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(BuildContext ctx, void Function(DateTime) set, {DateTime? initial}) async {
    final picked = await showDatePicker(
      context: ctx,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(1800),
      lastDate: DateTime(2100),
    );
    if (picked != null) set(picked);
  }

  Future<void> _submitRequest() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please complete required fields')));
      return;
    }
    
    final fullName = _fullNameCtrl.text.trim();
    final requestDate = DateTime.now();
    final dfIso = DateFormat("yyyy-MM-dd");

    final requestDetails = <String, dynamic>{
      'requestType': 'certificate_request',
      'recordType': _recordType,
      'recordDetails': {
        'fullName': fullName,
        'eventDate': _eventDate == null ? null : dfIso.format(_eventDate!),
        'eventPlace': _eventPlaceCtrl.text.trim(),
      },
      'requestInfo': {
        'purpose': _purpose,
        'requesterName': _requesterNameCtrl.text.trim(),
        'contactInfo': _contactInfoCtrl.text.trim(),
        'preferredPickupDate': _preferredPickupDate == null ? null : dfIso.format(_preferredPickupDate!),
        'remarks': _remarksCtrl.text.trim(),
        'status': _status.name,
        'requestDate': dfIso.format(requestDate),
      },
      'metadata': {
        'submittedAt': DateTime.now().toIso8601String(),
        'requestId': 'REQ-${DateTime.now().millisecondsSinceEpoch}',
      }
    };

    try {
      // Create a record entry for the certificate request
      await ref.read(recordsProvider.notifier).addRecord(
            RecordType.baptism, // You might want to add a new type for requests
            'Certificate Request: $fullName ($_recordType)',
            requestDate,
            notes: json.encode(requestDetails),
          );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Certificate request submitted successfully')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Request failed: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat.yMMMMd();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Certificate Request'),
        actions: [
          TextButton.icon(
            onPressed: _submitRequest,
            icon: const Icon(Icons.send_outlined),
            label: const Text('Submit'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Request Information
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Certificate Information', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _recordType,
                        items: const [
                          DropdownMenuItem(value: 'Baptism', child: Text('Baptism')),
                          DropdownMenuItem(value: 'Marriage', child: Text('Marriage')),
                          DropdownMenuItem(value: 'Confirmation', child: Text('Confirmation')),
                          DropdownMenuItem(value: 'Death', child: Text('Death')),
                        ],
                        onChanged: (v) => setState(() => _recordType = v ?? 'Baptism'),
                        decoration: const InputDecoration(labelText: 'Record Type'),
                        validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _fullNameCtrl,
                        decoration: const InputDecoration(labelText: 'Full Name'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text('Date of Event: ${_eventDate == null ? 'Not specified' : df.format(_eventDate!)}'),
                          ),
                          TextButton(
                            onPressed: () => _pickDate(context, (d) => setState(() => _eventDate = d), initial: _eventDate),
                            child: const Text('Pick Date'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _eventPlaceCtrl,
                        decoration: const InputDecoration(labelText: 'Place of Event'),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _purpose,
                        items: const [
                          DropdownMenuItem(value: 'School', child: Text('School')),
                          DropdownMenuItem(value: 'Employment', child: Text('Employment')),
                          DropdownMenuItem(value: 'Passport', child: Text('Passport')),
                          DropdownMenuItem(value: 'Others', child: Text('Others')),
                        ],
                        onChanged: (v) => setState(() => _purpose = v ?? 'School'),
                        decoration: const InputDecoration(labelText: 'Purpose'),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Requester Information
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Requester Information', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _requesterNameCtrl,
                        decoration: const InputDecoration(labelText: "Requester's Name"),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _contactInfoCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Contact Info (Phone / Email)',
                          hintText: 'e.g., +63 912 345 6789 or email@example.com',
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text('Preferred Pick-up Date: ${_preferredPickupDate == null ? 'Not specified' : df.format(_preferredPickupDate!)}'),
                          ),
                          TextButton(
                            onPressed: () => _pickDate(context, (d) => setState(() => _preferredPickupDate = d), initial: _preferredPickupDate),
                            child: const Text('Pick Date'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _remarksCtrl,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Remarks',
                          hintText: 'Any additional information or special requests...',
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Status Information
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Request Status', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.hourglass_empty, color: Colors.orange),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Status: ${_status.name.toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  const Text('Your request will be processed by parish staff. You will be contacted when ready for pickup.'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Submit button
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _submitRequest,
                  icon: const Icon(Icons.send),
                  label: const Text('Submit Certificate Request'),
                ),
              ),

              const SizedBox(height: 16),

              // Information card
              Card(
                color: Colors.blue.withValues(alpha: 0.05),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue),
                          const SizedBox(width: 8),
                          Text('Important Information', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text('• Processing time: 3-5 business days'),
                      const Text('• You will be contacted when your certificate is ready'),
                      const Text('• Please bring valid ID when picking up'),
                      const Text('• Certificate fee may apply upon pickup'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
