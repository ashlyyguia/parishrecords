import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'landing_common.dart';

class HomeSection extends StatelessWidget {
  const HomeSection({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isCompact = size.width < 1000;
    final topPadding = MediaQuery.of(context).padding.top + 80;

    return LandingCommon.diagonalBackground(
      child: SingleChildScrollView(
        child: Container(
          padding: EdgeInsets.fromLTRB(
            isCompact ? 24 : 64,
            topPadding + (isCompact ? 32 : 72),
            isCompact ? 24 : 64,
            64,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1280),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  isCompact
                      ? Column(
                          children: [
                            _HeroImage(),
                            const SizedBox(height: 52),
                            _HomeCopy(center: true),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(flex: 6, child: _HeroImage()),
                            const SizedBox(width: 72),
                            const Expanded(flex: 5, child: _HomeCopy()),
                          ],
                        ),
                  const SizedBox(height: 44),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroImage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Decorative ring behind image
        Positioned(
          bottom: -16,
          right: -16,
          child: Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.25),
                width: 32,
              ),
            ),
          ),
        ),
        Positioned(
          top: -12,
          left: -12,
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.15),
            ),
          ),
        ),
        AspectRatio(aspectRatio: 4 / 3, child: LandingCommon.churchImageCard()),
        // Floating stat badge
        Positioned(
          bottom: 20,
          left: 20,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: LandingCommon.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.people_outline,
                    color: LandingCommon.primary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Community',
                      style: LandingCommon.bodyStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    Text(
                      'Est. 1952',
                      style: LandingCommon.bodyStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HomeCopy extends StatelessWidget {
  const _HomeCopy({this.center = false});
  final bool center;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final titleSize = w < 400
        ? 34.0
        : (w < 600 ? 40.0 : (w < 1000 ? 48.0 : 58.0));
    final subtitleSize = w < 400
        ? 14.0
        : (w < 600 ? 15.0 : (w < 1000 ? 17.0 : 19.0));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        // Label badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: LandingCommon.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: LandingCommon.primary.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.church_outlined,
                size: 14,
                color: LandingCommon.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'Holy Rosary Parish',
                style: LandingCommon.bodyStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: LandingCommon.primary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Welcome to\nOur Sacred Community',
          textAlign: center ? TextAlign.center : TextAlign.start,
          style: LandingCommon.titleStyle(
            fontSize: titleSize,
            color: Colors.black87,
          ).copyWith(height: 1.1),
        ),
        const SizedBox(height: 20),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Text(
            'Discover upcoming liturgies, community gatherings, and important parish updates — all in one place, for you and your family.',
            textAlign: center ? TextAlign.center : TextAlign.start,
            style: LandingCommon.bodyStyle(
              fontSize: subtitleSize,
              color: Colors.black.withValues(alpha: 0.7),
            ),
          ),
        ),
        const SizedBox(height: 40),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          alignment: center ? WrapAlignment.center : WrapAlignment.start,
          children: [
            _CtaButton(
              label: 'Announcements',
              icon: Icons.campaign_outlined,
              onPressed: () => context.go('/announcements'),
              isPrimary: true,
            ),
            _CtaButton(
              label: 'Mass Times',
              icon: Icons.schedule_outlined,
              onPressed: () => context.go('/mass-time'),
            ),
            _CtaButton(
              label: 'Donate',
              icon: Icons.volunteer_activism_outlined,
              onPressed: () => context.go('/donations'),
            ),
          ],
        ),
      ],
    );
  }
}

class _CtaButton extends StatelessWidget {
  const _CtaButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.isPrimary = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    if (isPrimary) {
      return ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: LandingCommon.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
          textStyle: LandingCommon.bodyStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: LandingCommon.primary,
        side: BorderSide(
          color: LandingCommon.primary.withValues(alpha: 0.3),
          width: 1.5,
        ),
        backgroundColor: LandingCommon.primary.withValues(alpha: 0.05),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: LandingCommon.bodyStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
