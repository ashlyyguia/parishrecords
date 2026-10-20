import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'letter_certificate.dart';

/// Pieces shared by the Good Moral and No Record entry forms.

String? requiredField(String? v) =>
    (v == null || v.trim().isEmpty) ? 'Required' : null;

/// "Daughter" / "Son" — printed as "daughter of …".
class ChildOfField extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  const ChildOfField({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value == 'daughter' || value == 'son' ? value : null,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Daughter / Son *'),
      items: const [
        DropdownMenuItem(value: 'daughter', child: Text('Daughter')),
        DropdownMenuItem(value: 'son', child: Text('Son')),
      ],
      onChanged: onChanged,
      validator: (v) => v == null ? 'Required' : null,
    );
  }
}

/// Father's and mother's names, side by side on wide screens.
class ParentsFields extends StatelessWidget {
  final TextEditingController father;
  final TextEditingController mother;
  const ParentsFields({super.key, required this.father, required this.mother});

  @override
  Widget build(BuildContext context) {
    final f = TextFormField(
      controller: father,
      textCapitalization: TextCapitalization.words,
      decoration: const InputDecoration(
        labelText: "Father's name",
        hintText: 'e.g. Francisco Nuqui',
      ),
    );
    final m = TextFormField(
      controller: mother,
      textCapitalization: TextCapitalization.words,
      decoration: const InputDecoration(
        labelText: "Mother's name",
        hintText: 'e.g. Rosenda Abuton',
      ),
    );
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth >= 520
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: f),
                const SizedBox(width: 8),
                Expanded(child: m),
              ],
            )
          : Column(children: [f, const SizedBox(height: 8), m]),
    );
  }
}

/// Date issued with a Change button.
class DateIssuedField extends StatelessWidget {
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  const DateIssuedField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: const InputDecoration(labelText: 'Date issued *'),
      child: Row(
        children: [
          Expanded(child: Text(DateFormat.yMMMMd().format(value))),
          TextButton(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: value,
                firstDate: DateTime(1900),
                lastDate: DateTime(2100),
              );
              if (picked != null) onChanged(picked);
            },
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }
}

/// Signing priest and position, with quick picks for the parish priest and
/// the parish vicar.
class SignatoryFields extends StatelessWidget {
  final TextEditingController name;
  final TextEditingController position;
  const SignatoryFields({
    super.key,
    required this.name,
    required this.position,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final s in kCertificateSignatories)
              ActionChip(
                avatar: const Icon(Icons.person_outline, size: 18),
                label: Text(s.position),
                tooltip: s.name,
                onPressed: () {
                  name.text = s.name;
                  position.text = s.position;
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: name,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Signing priest *'),
          validator: requiredField,
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: position,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Position *',
            hintText: 'e.g. Parish Priest',
          ),
          validator: requiredField,
        ),
      ],
    );
  }
}
