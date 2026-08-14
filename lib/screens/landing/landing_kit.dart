import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/app_colors.dart';

/// Shared building blocks for the public landing pages.
///
/// Everything here mirrors the in-app dashboard design system: the Sky Azure
/// [AppColors] palette, flat bordered cards, sky-azure gradient heroes, tinted
/// icon badges, and Poppins typography — so the public site and the portal feel
/// like one product.
class LandingKit {
  LandingKit._();

  static const double maxContentWidth = 1200;

  /// Height taken up by the fixed glass navbar (keep page content clear of it).
  static double navSpace(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final top = MediaQuery.paddingOf(context).top;
    return (w < 480 ? 64.0 : 80.0) + top;
  }

  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 900;

  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 600;

  // ── Typography (Poppins, matching the dashboard) ─────────────────────
  static TextStyle display(double size, {Color color = AppColors.ink}) =>
      GoogleFonts.poppins(
        fontSize: size,
        fontWeight: FontWeight.w800,
        color: color,
        height: 1.08,
        letterSpacing: -0.5,
      );

  static TextStyle heading(double size, {Color color = AppColors.ink}) =>
      GoogleFonts.poppins(
        fontSize: size,
        fontWeight: FontWeight.w700,
        color: color,
        height: 1.2,
        letterSpacing: -0.2,
      );

  static TextStyle body(
    double size, {
    Color color = AppColors.slate600,
    FontWeight weight = FontWeight.w400,
    double height = 1.6,
  }) => GoogleFonts.poppins(
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
  );

  static TextStyle eyebrow({Color color = AppColors.primary}) =>
      GoogleFonts.poppins(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: 2.5,
      );
}

/// Scrollable public page: soft blue scaffold, room for the navbar, centered
/// max-width column with consistent gutters. Pass the page's [slivers]-free
/// [children] which are laid out in a Column.
class LandingPage extends StatelessWidget {
  const LandingPage({super.key, required this.children, this.controller});

  final List<Widget> children;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final compact = LandingKit.isCompact(context);
    final gutter = compact ? 20.0 : 48.0;

    return DecoratedBox(
      decoration: const BoxDecoration(gradient: _pageWash),
      child: SingleChildScrollView(
        controller: controller,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            gutter,
            LandingKit.navSpace(context) + (compact ? 20 : 32),
            gutter,
            compact ? 40 : 64,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: LandingKit.maxContentWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const _pageWash = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [AppColors.tint, AppColors.scaffold],
    stops: [0.0, 0.35],
  );
}

/// Sky-azure gradient hero band — the public-page counterpart of the dashboard
/// header. Eyebrow + big title + subtitle + optional action buttons, with a
/// faint decorative glyph bleeding off the corner.
class LandingHero extends StatelessWidget {
  const LandingHero({
    super.key,
    required this.eyebrow,
    required this.title,
    this.subtitle,
    this.glyph = Icons.church_rounded,
    this.actions = const <Widget>[],
    this.trailing,
  });

  final String eyebrow;
  final String title;
  final String? subtitle;
  final IconData glyph;
  final List<Widget> actions;

  /// Optional widget shown to the right on wide screens (e.g. hero image).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final compact = LandingKit.isCompact(context);
    final pad = compact ? 24.0 : 44.0;

    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
          ),
          child: Text(
            eyebrow,
            style: LandingKit.eyebrow(color: Colors.white),
          ),
        ),
        SizedBox(height: compact ? 16 : 20),
        Text(
          title,
          style: LandingKit.display(
            compact ? 32 : 46,
            color: Colors.white,
          ),
        ),
        if (subtitle != null) ...[
          SizedBox(height: compact ? 12 : 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Text(
              subtitle!,
              style: LandingKit.body(
                compact ? 14.5 : 16,
                color: Colors.white.withValues(alpha: 0.92),
              ),
            ),
          ),
        ],
        if (actions.isNotEmpty) ...[
          SizedBox(height: compact ? 22 : 30),
          Wrap(spacing: 12, runSpacing: 12, children: actions),
        ],
      ],
    );

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryDark, AppColors.primary, AppColors.accent],
        ),
        borderRadius: BorderRadius.circular(compact ? 24 : 30),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.28),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(compact ? 24 : 30),
        child: Stack(
          children: [
            Positioned(
              right: -24,
              top: -28,
              child: Icon(
                glyph,
                size: compact ? 170 : 230,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            if (trailing != null && !compact)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(flex: 6, child: copy),
                  const SizedBox(width: 36),
                  Expanded(flex: 5, child: trailing!),
                ],
              )
            else
              copy,
          ],
        ),
      ),
    );
  }
}

/// In-page section header: tinted brand icon badge + title (+ optional subtitle),
/// mirroring the app's PageHeader treatment.
class LandingSectionHeader extends StatelessWidget {
  const LandingSectionHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final compact = LandingKit.isMobile(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.tint,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.tintStrong),
          ),
          child: Icon(icon, color: AppColors.primary, size: compact ? 22 : 26),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: LandingKit.heading(compact ? 21 : 26)),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(subtitle!, style: LandingKit.body(compact ? 13.5 : 15)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Rounded, bordered image frame for the church photo — flat card styling with
/// a soft brand-tinted glow.
class LandingImageFrame extends StatelessWidget {
  const LandingImageFrame({
    super.key,
    this.aspectRatio = 4 / 3,
    this.asset = 'assets/images/hero_parish.png',
  });

  final double aspectRatio;
  final String asset;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white, width: 6),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.22),
              blurRadius: 34,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.asset(asset, fit: BoxFit.cover),
        ),
      ),
    );
  }
}

/// Tinted brand pill with an icon + label (used for eyebrows/among cards).
class LandingPill extends StatelessWidget {
  const LandingPill({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.tint,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.tintStrong),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.primary),
          const SizedBox(width: 7),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryDark,
            ),
          ),
        ],
      ),
    );
  }
}

/// Primary (filled sky-azure) or secondary (outlined) landing button.
class LandingButton extends StatelessWidget {
  const LandingButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
    this.onDark = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool primary;

  /// True when the button sits on a dark (hero) surface.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.poppins(fontSize: 14.5, fontWeight: FontWeight.w600);
    const pad = EdgeInsets.symmetric(horizontal: 22, vertical: 16);
    final radius = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );

    if (primary) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label, style: style),
        style: FilledButton.styleFrom(
          backgroundColor: onDark ? Colors.white : AppColors.primary,
          foregroundColor: onDark ? AppColors.primaryDark : Colors.white,
          padding: pad,
          shape: radius,
          elevation: 0,
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label, style: style),
      style: OutlinedButton.styleFrom(
        foregroundColor: onDark ? Colors.white : AppColors.primary,
        backgroundColor: onDark
            ? Colors.white.withValues(alpha: 0.12)
            : AppColors.tint,
        side: BorderSide(
          color: onDark
              ? Colors.white.withValues(alpha: 0.4)
              : AppColors.tintStrong,
        ),
        padding: pad,
        shape: radius,
      ),
    );
  }
}
