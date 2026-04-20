import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'landing_common.dart';

class AboutHistorySection extends StatelessWidget {
  const AboutHistorySection({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isCompact = size.width < 900;

    return LandingCommon.diagonalBackground(
      child: Container(
        padding: const EdgeInsets.fromLTRB(28, 92, 28, 28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: isCompact
                ? Column(
                    children: [
                      const SizedBox(height: 18),
                      AspectRatio(
                        aspectRatio: 16 / 10,
                        child: LandingCommon.churchImageCard(),
                      ),
                      const SizedBox(height: 22),
                      _buildTextContent(),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 6,
                        child: AspectRatio(
                          aspectRatio: 16 / 10,
                          child: LandingCommon.churchImageCard(),
                        ),
                      ),
                      const SizedBox(width: 28),
                      Expanded(flex: 5, child: _buildTextContent()),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Holy Rosary Parish was established in 1952 to serve the growing Catholic community in Oroquieta City. What began as a small chapel has grown into a vibrant parish dedicated to spiritual growth, sacramental service, and community outreach.',
          style: GoogleFonts.poppins(
            fontSize: 14,
            height: 1.6,
            color: Colors.black.withValues(alpha: 0.75),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Over the decades, the parish has expanded its ministries, improved its facilities, and embraced modern solutions to better serve the parishioners.',
          style: GoogleFonts.poppins(
            fontSize: 14,
            height: 1.6,
            color: Colors.black.withValues(alpha: 0.75),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Key Milestones:',
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 8),
        _MilestoneItem(year: '1952', text: 'Parish officially founded.'),
        _MilestoneItem(year: '1988', text: 'Major church renovation completed.'),
        _MilestoneItem(year: '2005', text: 'Parish community hall inaugurated.'),
        _MilestoneItem(year: '2026', text: 'Launch of Parish Operational Management System with ML Kit OCR.'),
      ],
    );
  }
}

class _MilestoneItem extends StatelessWidget {
  final String year;
  final String text;

  const _MilestoneItem({required this.year, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '• $year — ',
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: Colors.black.withValues(alpha: 0.75),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
