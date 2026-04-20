import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

class LandingNavBar extends StatelessWidget {
  const LandingNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onItemTap,
  });

  final List<LandingNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onItemTap;

  static const _purple = Color(0xFF5C57FF);
  static const _bg = Color(0xFFD9D9D9);

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.width < 980;

    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        height: 72,
        decoration: BoxDecoration(
          color: _bg,
          border: Border(
            top: BorderSide(color: _purple, width: 3),
            bottom: BorderSide(color: _purple, width: 3),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              _BrandMark(),
              const SizedBox(width: 14),
              Text(
                'HOLY ROSARY',
                style: GoogleFonts.merriweather(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Colors.black,
                ),
              ),
              const Spacer(),
              if (!isCompact)
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (int i = 0; i < items.length; i++)
                            if (items[i].children != null &&
                                items[i].children!.isNotEmpty)
                              _NavDropdownButton(
                                item: items[i],
                                isActive: i == currentIndex,
                                currentRoute: GoRouterState.of(
                                  context,
                                ).uri.toString(),
                              )
                            else
                              _NavTextButton(
                                label: items[i].label,
                                isActive: i == currentIndex,
                                onPressed: () => onItemTap(i),
                              ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                _CompactNav(
                  items: items,
                  currentIndex: currentIndex,
                  onTap: onItemTap,
                ),
              const SizedBox(width: 18),
              _LoginButton(onPressed: () => context.go('/login')),
            ],
          ),
        ),
      ),
    );
  }
}

class LandingNavItem {
  final String label;
  final String route;
  final List<LandingNavItem>? children;

  const LandingNavItem(this.label, this.route, {this.children});
}

class _BrandMark extends StatelessWidget {
  static const _purple = Color(0xFF5C57FF);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.of(context).devicePixelRatio;
        final maxW = constraints.maxWidth.isFinite ? constraints.maxWidth : 44;
        final cacheW = (maxW * dpr).round().clamp(1, 256);

        return Container(
          width: 44,
          height: 44,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _purple, width: 2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.asset(
              'assets/icons/app_icon.png',
              fit: BoxFit.cover,
              cacheWidth: cacheW,
            ),
          ),
        );
      },
    );
  }
}

class _NavDropdownButton extends StatelessWidget {
  final LandingNavItem item;
  final bool isActive;
  final String currentRoute;

  const _NavDropdownButton({
    required this.item,
    required this.isActive,
    required this.currentRoute,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: item.label,
      onSelected: (route) => context.go(route),
      itemBuilder: (context) => [
        for (final child in item.children!)
          PopupMenuItem<String>(
            value: child.route,
            child: Text(
              child.label,
              style: GoogleFonts.merriweather(
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ],
      child: TextButton(
        onPressed: null,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          foregroundColor: Colors.black,
        ),
        child: Row(
          children: [
            Text(
              item.label,
              style: GoogleFonts.merriweather(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                fontWeight: isActive ? FontWeight.w900 : FontWeight.w800,
                decoration: isActive ? TextDecoration.underline : null,
                decorationThickness: 2,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.expand_more, size: 14),
          ],
        ),
      ),
    );
  }
}

class _NavTextButton extends StatelessWidget {
  const _NavTextButton({
    required this.label,
    required this.isActive,
    required this.onPressed,
  });

  final String label;
  final bool isActive;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        foregroundColor: Colors.black,
      ),
      child: Text(
        label,
        style: GoogleFonts.merriweather(
          fontSize: 12,
          fontStyle: FontStyle.italic,
          fontWeight: isActive ? FontWeight.w900 : FontWeight.w800,
          decoration: isActive ? TextDecoration.underline : null,
          decorationThickness: 2,
        ),
      ),
    );
  }
}

class _CompactNav extends StatelessWidget {
  const _CompactNav({
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  final List<LandingNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: 'Sections',
      initialValue: currentIndex,
      onSelected: onTap,
      itemBuilder: (context) => [
        for (int i = 0; i < items.length; i++)
          PopupMenuItem<int>(value: i, child: Text(items[i].label)),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Text(
              items[currentIndex].label,
              style: GoogleFonts.merriweather(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.expand_more, size: 18),
          ],
        ),
      ),
    );
  }
}

class _LoginButton extends StatelessWidget {
  const _LoginButton({required this.onPressed});

  final VoidCallback onPressed;

  static const _purple = Color(0xFF5C57FF);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _purple,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        icon: const Icon(Icons.login_rounded, size: 16),
        label: Text(
          'Login',
          style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
