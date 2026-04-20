import 'package:flutter/material.dart';
import 'landing_common.dart';

class ContactSection extends StatelessWidget {
  const ContactSection({super.key});

  @override
  Widget build(BuildContext context) {
    return LandingCommon.sectionShell(
      title: 'Contact Us',
      subtitle: 'Have a question or need spiritual guidance? We are here to listen and help.',
      left: LandingCommon.churchImageCard(),
      right: LandingCommon.contentCard(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.mail_outline, color: LandingCommon.primary, size: 28),
                const SizedBox(width: 12),
                Text(
                  'Send a Message',
                  style: LandingCommon.titleStyle(fontSize: 22),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Fill out the form below and our parish office will get back to you soon.',
              style: LandingCommon.bodyStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            _ContactField(label: 'Full Name', icon: Icons.person_outline),
            const SizedBox(height: 16),
            _ContactField(label: 'Email Address', icon: Icons.alternate_email),
            const SizedBox(height: 16),
            _ContactField(label: 'Message', icon: Icons.chat_bubble_outline, maxLines: 4),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text('Send Message'),
              style: ElevatedButton.styleFrom(
                backgroundColor: LandingCommon.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 4,
                shadowColor: LandingCommon.primary.withValues(alpha: 0.4),
                textStyle: LandingCommon.bodyStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactField extends StatelessWidget {
  const _ContactField({required this.label, required this.icon, this.maxLines = 1});
  final String label;
  final IconData icon;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      maxLines: maxLines,
      style: LandingCommon.bodyStyle(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: LandingCommon.bodyStyle(fontSize: 14, color: Colors.grey.shade500),
        alignLabelWithHint: maxLines > 1,
        prefixIcon: Padding(
          padding: EdgeInsets.only(bottom: maxLines > 1 ? (maxLines * 16.0 - 24) : 0),
          child: Icon(icon, color: Colors.grey.shade400, size: 20),
        ),
        filled: true,
        fillColor: LandingCommon.bg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: LandingCommon.primary, width: 2),
        ),
      ),
    );
  }
}
