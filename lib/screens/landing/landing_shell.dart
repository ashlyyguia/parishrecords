import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'landing_common.dart';

class LandingShell extends StatelessWidget {
  const LandingShell({super.key, required this.child});

  final Widget child;

  final List<_NavItem> _items = const [
    _NavItem('HOME', '/'),
    _NavItem('ABOUT', '/about'),
    _NavItem('MASS TIME', '/mass-time'),
    _NavItem('DONATIONS', '/donations'),
    _NavItem('ANNOUNCEMENT', '/announcements'),
    _NavItem('CONTACT US', '/contact'),
  ];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final currentIndex = _items.indexWhere((item) => item.path == location);

    return Scaffold(
      backgroundColor: LandingCommon.bg,
      body: Stack(
        children: [
          Positioned.fill(child: child),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _GlassNavBar(
              items: _items,
              currentIndex: currentIndex >= 0 ? currentIndex : 0,
              location: location,
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem {
  final String label;
  final String path;
  const _NavItem(this.label, this.path);
}

class _GlassNavBar extends StatelessWidget {
  const _GlassNavBar({
    required this.items,
    required this.currentIndex,
    required this.location,
  });

  final List<_NavItem> items;
  final int currentIndex;
  final String location;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isCompact = width < 1200;
    final isTiny = width < 480;
    final topPadding = MediaQuery.of(context).padding.top;
    final barHeight = (isTiny ? 64.0 : 80.0) + topPadding;
    final navPadding = width >= 1400 ? 16.0 : 10.0;

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.only(top: topPadding),
          height: barHeight,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.7),
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: isTiny ? 12 : 24),
            child: Row(
              children: [
                _BrandMark(size: isTiny ? 40 : 48),
                if (!isTiny) ...[
                  SizedBox(width: isCompact ? 8 : 16),
                  Text(
                    'HOLY ROSARY',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LandingCommon.titleStyle(
                      fontSize: isCompact ? 16 : 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
                const Spacer(),
                if (!isCompact)
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (int i = 0; i < items.length; i++)
                            _NavTextButton(
                              label: items[i].label,
                              isActive: i == currentIndex,
                              horizontalPadding: navPadding,
                              onPressed: () => context.go(items[i].path),
                            ),
                        ],
                      ),
                    ),
                  )
                else
                  _CompactNav(items: items, currentIndex: currentIndex),
                SizedBox(width: isTiny ? 8 : 16),
                _LoginButton(
                  onPressed: () => context.go('/login'),
                  compact: isTiny,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.white, Color(0xFFF1F5F9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: LandingCommon.primary.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.16),
        child: Image.asset('assets/images/image2.png', fit: BoxFit.contain),
      ),
    );
  }
}

class _NavTextButton extends StatefulWidget {
  const _NavTextButton({
    required this.label,
    required this.isActive,
    required this.onPressed,
    this.horizontalPadding = 16,
  });

  final String label;
  final bool isActive;
  final VoidCallback onPressed;
  final double horizontalPadding;

  @override
  State<_NavTextButton> createState() => _NavTextButtonState();
}

class _NavTextButtonState extends State<_NavTextButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: widget.horizontalPadding,
            vertical: 8,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Text(
                widget.label,
                style: LandingCommon.bodyStyle(
                  fontSize: 13,
                  fontWeight: widget.isActive
                      ? FontWeight.w700
                      : FontWeight.w600,
                  color: widget.isActive || _isHovered
                      ? LandingCommon.primary
                      : const Color(0xFF475569),
                ).copyWith(letterSpacing: 0.5),
              ),
              if (widget.isActive)
                Positioned(
                  bottom: -6,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 2,
                    decoration: BoxDecoration(
                      color: LandingCommon.primary,
                      borderRadius: BorderRadius.circular(2),
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

class _CompactNav extends StatelessWidget {
  const _CompactNav({required this.items, required this.currentIndex});

  final List<_NavItem> items;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      key: ValueKey('compact_nav_$currentIndex'),
      tooltip: 'Menu',
      initialValue: currentIndex,
      onSelected: (i) => context.go(items[i].path),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      itemBuilder: (context) => [
        for (int i = 0; i < items.length; i++)
          PopupMenuItem<int>(
            value: i,
            child: Text(
              items[i].label,
              style: LandingCommon.bodyStyle(
                fontWeight: i == currentIndex
                    ? FontWeight.bold
                    : FontWeight.normal,
                color: i == currentIndex ? LandingCommon.primary : null,
              ),
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Text(
              items[currentIndex].label,
              style: LandingCommon.bodyStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: LandingCommon.primary,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.expand_more,
              size: 18,
              color: LandingCommon.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginButton extends StatelessWidget {
  const _LoginButton({required this.onPressed, this.compact = false});

  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [LandingCommon.primaryLight, LandingCommon.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: LandingCommon.primary.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          shadowColor: Colors.transparent,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 24,
            vertical: compact ? 12 : 16,
          ),
          minimumSize: Size(compact ? 44 : 0, compact ? 44 : 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        child: compact
            ? const Icon(Icons.login_rounded, size: 20)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.login_rounded, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Portal Login',
                    style: LandingCommon.bodyStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
