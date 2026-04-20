import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'landing_common.dart';

class AboutIntroSection extends StatelessWidget {
  const AboutIntroSection({super.key});

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
                      _buildTextContent(center: true),
                    ],
                  )
                : Row(
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

  Widget _buildTextContent({bool center = false}) {
    return Column(
      crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'ABOUT HOLY ROSARY PARISH',
          textAlign: center ? TextAlign.center : TextAlign.start,
          style: GoogleFonts.merriweather(
            fontSize: 38,
            fontWeight: FontWeight.w900,
            fontStyle: FontStyle.italic,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '"Serving Oroquieta City with faith, service, and community since 1952."',
          textAlign: center ? TextAlign.center : TextAlign.start,
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontStyle: FontStyle.italic,
            color: Colors.black.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}
