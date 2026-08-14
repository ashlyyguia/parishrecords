import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/app_colors.dart';
import '../../widgets/app_card.dart';
import 'landing_kit.dart';

class ContactSection extends StatelessWidget {
  const ContactSection({super.key});

  @override
  Widget build(BuildContext context) {
    final compact = LandingKit.isCompact(context);

    final aside = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: const [
        _InfoTile(
          icon: Icons.location_on_rounded,
          title: 'Visit us',
          lines: ['Holy Rosary Parish', 'Oroquieta City, Misamis Occidental'],
        ),
        SizedBox(height: 12),
        _InfoTile(
          icon: Icons.call_rounded,
          title: 'Call the office',
          lines: ['(088) 531-1234'],
        ),
        SizedBox(height: 12),
        _InfoTile(
          icon: Icons.mail_rounded,
          title: 'Email us',
          lines: ['parishoffice@holyrosary.ph'],
        ),
        SizedBox(height: 12),
        _InfoTile(
          icon: Icons.access_time_rounded,
          title: 'Office hours',
          lines: ['Monday – Saturday', '8:00 AM – 5:00 PM'],
        ),
      ],
    );

    return LandingPage(
      children: [
        const LandingHero(
          eyebrow: 'CONTACT US',
          title: 'We are here\nto listen',
          subtitle:
              'Have a question or need spiritual guidance? Reach out to the '
              'parish office and we will get back to you soon.',
          glyph: Icons.forum_rounded,
        ),
        SizedBox(height: compact ? 28 : 44),
        if (compact) ...[
          aside,
          const SizedBox(height: 20),
          const _ContactForm(),
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: aside),
              const SizedBox(width: 40),
              const Expanded(flex: 6, child: _ContactForm()),
            ],
          ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.title,
    required this.lines,
  });

  final IconData icon;
  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: AppColors.brandGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: LandingKit.eyebrow(color: AppColors.slate500)
                      .copyWith(letterSpacing: 1.4),
                ),
                const SizedBox(height: 5),
                for (final l in lines)
                  Text(l, style: LandingKit.body(14.5, color: AppColors.ink, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactForm extends StatelessWidget {
  const _ContactForm();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Send a message', style: LandingKit.heading(22)),
          const SizedBox(height: 6),
          Text(
            'Fill out the form and our parish office will get back to you.',
            style: LandingKit.body(14),
          ),
          const SizedBox(height: 22),
          const _Field(label: 'Full name', icon: Icons.person_outline_rounded),
          const SizedBox(height: 14),
          const _Field(
            label: 'Email address',
            icon: Icons.alternate_email_rounded,
          ),
          const SizedBox(height: 14),
          const _Field(
            label: 'Message',
            icon: Icons.chat_bubble_outline_rounded,
            maxLines: 4,
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Message sent! We will contact you soon.'),
                ),
              );
            },
            icon: const Icon(Icons.send_rounded, size: 18),
            label: Text(
              'Send message',
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 17),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.icon,
    this.maxLines = 1,
  });

  final String label;
  final IconData icon;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      maxLines: maxLines,
      style: LandingKit.body(14.5, color: AppColors.ink),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: LandingKit.body(14, color: AppColors.slate500),
        alignLabelWithHint: maxLines > 1,
        prefixIcon: Padding(
          padding: EdgeInsets.only(bottom: maxLines > 1 ? (maxLines * 16.0 - 24) : 0),
          child: Icon(icon, color: AppColors.slate400, size: 20),
        ),
        filled: true,
        fillColor: AppColors.field,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
      ),
    );
  }
}
