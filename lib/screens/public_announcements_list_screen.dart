import 'dart:ui';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/announcement.dart';
import '../services/announcements_repository.dart';

class PublicAnnouncementsListScreen extends StatefulWidget {
  const PublicAnnouncementsListScreen({super.key});

  static final GlobalKey _heroSectionKey = GlobalKey();
  static final GlobalKey _announcementsSectionKey = GlobalKey();
  static final GlobalKey _contactSectionKey = GlobalKey();

  @override
  State<PublicAnnouncementsListScreen> createState() =>
      _PublicAnnouncementsListScreenState();
}

class _HeroImageCard extends StatelessWidget {
  const _HeroImageCard({required this.animation});

  final Animation<Offset> animation;

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: animation,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFD4AF37), width: 1.4),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD4AF37).withValues(alpha: 0.25),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: Image.asset(
                'assets/images/hero_parish.jpg',
                fit: BoxFit.cover,
              ),
            ),
            Container(
              color: Colors.black.withValues(alpha: 0.75),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Follow the word of Christ',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                  Row(
                    children: const [
                      Icon(Icons.facebook, size: 16, color: Colors.white70),
                      SizedBox(width: 8),
                      Icon(Icons.camera_alt, size: 16, color: Colors.white70),
                      SizedBox(width: 8),
                      Icon(
                        Icons.play_circle_fill,
                        size: 16,
                        color: Colors.white70,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RadialLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = const Color(0xFFD4AF37).withValues(alpha: 0.7)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    const rays = 12;
    final radius = size.width / 2;
    for (var i = 0; i < rays; i++) {
      final angle = (i / rays) * math.pi * 2;
      final end = Offset(
        center.dx + radius * 0.9 * math.cos(angle),
        center.dy + radius * 0.9 * math.sin(angle),
      );
      canvas.drawLine(center, end, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RadialLinesPainter oldDelegate) => false;
}

class _HeroTextBlock extends StatelessWidget {
  const _HeroTextBlock({
    required this.theme,
    required this.opacity,
    required this.slide,
    required this.onAnnouncementsTap,
    required this.onContactTap,
    required this.isMobile,
  });

  final ThemeData theme;
  final Animation<double> opacity;
  final Animation<Offset> slide;
  final VoidCallback onAnnouncementsTap;
  final VoidCallback onContactTap;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: opacity,
      child: SlideTransition(
        position: slide,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.volume_up_rounded,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.95),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Announcements & parish life',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Stack(
              children: [
                const Positioned(
                  left: -10,
                  top: -6,
                  child: _HeroRadialDecoration(),
                ),
                Text(
                  'CHURCH\nSUNDAY SERVICES',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: isMobile ? 30 : 38,
                    height: 1.1,
                    letterSpacing: 1.2,
                    color: const Color(0xFFD4AF37),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Text(
                    'Two Liberties Heaven Church',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.92),
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Pastor Andrew Mills',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.92),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD4AF37),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'PASTOR',
                          style: GoogleFonts.poppins(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.1,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                'Discover upcoming liturgies, community gatherings, and important updates for you and your family.',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  height: 1.6,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _HeroCtaButton(
                  label: 'View announcements',
                  onTap: onAnnouncementsTap,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroCtaButton extends StatefulWidget {
  const _HeroCtaButton({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  State<_HeroCtaButton> createState() => _HeroCtaButtonState();
}

class _HeroCtaButtonState extends State<_HeroCtaButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover ? 1.04 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFD4AF37),
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          onPressed: widget.onTap,
          child: Text(
            widget.label.toUpperCase(),
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.1,
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroRadialDecoration extends StatelessWidget {
  const _HeroRadialDecoration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      height: 30,
      child: CustomPaint(painter: _RadialLinesPainter()),
    );
  }
}

class _PublicAnnouncementsListScreenState
    extends State<PublicAnnouncementsListScreen>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  bool _scrolled = false;

  int? _hoveredCardIndex;

  final _contactFormKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  bool _isSendingContact = false;

  late final AnimationController _heroController;
  late final Animation<Offset> _heroTextOffset;
  late final Animation<double> _heroOpacity;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);

    _heroController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _heroTextOffset =
        Tween<Offset>(begin: const Offset(-0.05, 0), end: Offset.zero).animate(
          CurvedAnimation(parent: _heroController, curve: Curves.easeOutCubic),
        );
    _heroOpacity = CurvedAnimation(
      parent: _heroController,
      curve: Curves.easeOut,
    );

    // Play hero entrance animation shortly after first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _heroController.forward();
      }
    });
  }

  void _handleScroll() {
    final shouldBeScrolled = _scrollController.offset > 8;
    if (shouldBeScrolled != _scrolled) {
      setState(() {
        _scrolled = shouldBeScrolled;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _heroController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = AnnouncementsRepository();

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 800;
          return StreamBuilder<List<Announcement>>(
            stream: repo.watchPublicActive(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                );
              }
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Failed to load announcements: ${snapshot.error}',
                    ),
                  ),
                );
              }
              final items = snapshot.data ?? const <Announcement>[];

              Announcement? featured;
              List<Announcement> others = items;
              if (items.isNotEmpty) {
                featured = items.firstWhere(
                  (a) => a.pinned,
                  orElse: () => items.first,
                );
                others = items.where((a) => a.id != featured!.id).toList();
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildNavBar(context, isMobile),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildHeroSection(context, featured, isMobile),
                          _buildAnnouncementsSection(
                            context,
                            featured,
                            others,
                            isMobile,
                          ),
                          _buildContactSection(context, isMobile),
                          _buildFooter(context),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildNavBar(BuildContext context, bool isMobile) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 32,
        vertical: 14,
      ),
      decoration: BoxDecoration(
        color: _scrolled
            ? const Color(0xFF050509).withValues(alpha: 0.96)
            : const Color(0xFF050509).withValues(alpha: 0.80),
        boxShadow: _scrolled
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ]
            : const [],
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Row(
            children: [
              Text(
                'Holy Parish',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 20,
                  color: const Color(0xFFD4AF37),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              if (!isMobile)
                Row(
                  children: [
                    TextButton(
                      onPressed: () {
                        _scrollToSection(
                          PublicAnnouncementsListScreen._heroSectionKey,
                        );
                      },
                      child: Text(
                        'HOME',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          letterSpacing: 1.2,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        _scrollToSection(
                          PublicAnnouncementsListScreen
                              ._announcementsSectionKey,
                        );
                      },
                      child: Text(
                        'ANNOUNCEMENTS',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          letterSpacing: 1.2,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        _scrollToSection(
                          PublicAnnouncementsListScreen._contactSectionKey,
                        );
                      },
                      child: Text(
                        'CONTACT',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          letterSpacing: 1.2,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 24),
                    SizedBox(
                      width: 210,
                      child: TextField(
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.white,
                        ),
                        cursorColor: const Color(0xFFD4AF37),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          hintText: 'Search',
                          hintStyle: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.6),
                          ),
                          prefixIcon: const Icon(
                            Icons.search,
                            size: 18,
                            color: Colors.white70,
                          ),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.06),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(999),
                            borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.18),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(999),
                            borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.18),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(999),
                            borderSide: const BorderSide(
                              color: Color(0xFFD4AF37),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFD4AF37),
                        side: const BorderSide(color: Color(0xFFD4AF37)),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(context).pushNamed('/login');
                      },
                      child: Text(
                        'LOGIN',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ],
                )
              else
                IconButton(
                  icon: const Icon(Icons.login),
                  tooltip: 'Login',
                  onPressed: () {
                    Navigator.of(context).pushNamed('/login');
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroSection(
    BuildContext context,
    Announcement? featured,
    bool isMobile,
  ) {
    final theme = Theme.of(context);
    final width = MediaQuery.of(context).size.width;
    final useStackedLayout = width < 800;

    return Column(
      key: PublicAnnouncementsListScreen._heroSectionKey,
      children: [
        AspectRatio(
          aspectRatio: useStackedLayout ? 4 / 5 : 21 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: _GoldParticlesPainter(repaint: _heroController),
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF0A0A0A), Color(0xFF151515)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: useStackedLayout ? 16 : 48,
                  vertical: useStackedLayout ? 20 : 28,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: useStackedLayout
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _HeroImageCard(animation: _heroTextOffset),
                              const SizedBox(height: 24),
                              _HeroTextBlock(
                                theme: theme,
                                opacity: _heroOpacity,
                                slide: _heroTextOffset,
                                onAnnouncementsTap: () {
                                  _scrollToSection(
                                    PublicAnnouncementsListScreen
                                        ._announcementsSectionKey,
                                  );
                                },
                                onContactTap: () {
                                  _scrollToSection(
                                    PublicAnnouncementsListScreen
                                        ._contactSectionKey,
                                  );
                                },
                                isMobile: true,
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(
                                flex: 5,
                                child: _HeroImageCard(
                                  animation: _heroTextOffset,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 6,
                                child: _HeroTextBlock(
                                  theme: theme,
                                  opacity: _heroOpacity,
                                  slide: _heroTextOffset,
                                  onAnnouncementsTap: () {
                                    _scrollToSection(
                                      PublicAnnouncementsListScreen
                                          ._announcementsSectionKey,
                                    );
                                  },
                                  onContactTap: () {
                                    _scrollToSection(
                                      PublicAnnouncementsListScreen
                                          ._contactSectionKey,
                                    );
                                  },
                                  isMobile: false,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Featured announcement block under the banner
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 16 : 32,
            vertical: isMobile ? 16 : 24,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                crossAxisAlignment: isMobile
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.start,
                children: [
                  if (featured != null)
                    Card(
                      elevation: 3,
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _openDetails(context, featured.id),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (featured.imageUrl != null)
                              AspectRatio(
                                aspectRatio: isMobile ? 16 / 9 : 21 / 9,
                                child: Image.network(
                                  featured.imageUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const ColoredBox(color: Colors.grey),
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Featured Event',
                                    style: theme.textTheme.labelMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    featured.title,
                                    style: theme.textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    featured.description,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${featured.location} • ${featured.eventDateTime}',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: 12),
                                  FilledButton(
                                    onPressed: () =>
                                        _openDetails(context, featured.id),
                                    child: const Text('View Details'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Text(
                      'No upcoming featured events yet. Please check back soon.',
                      style: theme.textTheme.bodyMedium,
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAnnouncementsSection(
    BuildContext context,
    Announcement? featured,
    List<Announcement> others,
    bool isMobile,
  ) {
    final theme = Theme.of(context);
    final itemsToShow = others.isEmpty && featured != null
        ? [featured]
        : others;

    return Container(
      key: PublicAnnouncementsListScreen._announcementsSectionKey,
      color: theme.colorScheme.surface.withValues(alpha: 0.02),
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 32,
        vertical: 28,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Latest announcements',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Browse upcoming masses, ministries, and community events.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!isMobile)
                    TextButton(
                      onPressed: () {
                        _scrollToSection(
                          PublicAnnouncementsListScreen._contactSectionKey,
                        );
                      },
                      child: const Text('View calendar'),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (itemsToShow.isEmpty)
                Text(
                  'No active announcements at the moment. Please check back soon.',
                  style: theme.textTheme.bodyMedium,
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: isMobile ? 1 : 3,
                    mainAxisSpacing: 18,
                    crossAxisSpacing: 18,
                    childAspectRatio: 4 / 3,
                  ),
                  itemCount: itemsToShow.length,
                  itemBuilder: (context, index) {
                    final a = itemsToShow[index];
                    final isHovered = !isMobile && _hoveredCardIndex == index;
                    return MouseRegion(
                      onEnter: (_) {
                        if (!isMobile) {
                          setState(() {
                            _hoveredCardIndex = index;
                          });
                        }
                      },
                      onExit: (_) {
                        if (!isMobile && _hoveredCardIndex == index) {
                          setState(() {
                            _hoveredCardIndex = null;
                          });
                        }
                      },
                      child: AnimatedScale(
                        scale: isHovered ? 1.02 : 1.0,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        child: InkWell(
                          onTap: () => _openDetails(context, a.id),
                          child: Card(
                            clipBehavior: Clip.antiAlias,
                            elevation: isHovered ? 4 : 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (a.imageUrl != null)
                                  AspectRatio(
                                    aspectRatio: 16 / 9,
                                    child: Image.network(
                                      a.imageUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              const ColoredBox(
                                                color: Colors.grey,
                                              ),
                                    ),
                                  ),
                                Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          if (a.pinned)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                              margin: const EdgeInsets.only(
                                                right: 8,
                                              ),
                                              decoration: BoxDecoration(
                                                color: theme.colorScheme.primary
                                                    .withValues(alpha: 0.1),
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                              ),
                                              child: Text(
                                                'Pinned',
                                                style: theme
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(
                                                      color: theme
                                                          .colorScheme
                                                          .primary,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                              ),
                                            ),
                                          Text(
                                            a.location,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                                  color: theme
                                                      .colorScheme
                                                      .onSurface
                                                      .withValues(alpha: 0.7),
                                                ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        a.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '${a.eventDateTime}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: theme.colorScheme.onSurface
                                                  .withValues(alpha: 0.75),
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContactSection(BuildContext context, bool isMobile) {
    final theme = Theme.of(context);
    return Container(
      key: PublicAnnouncementsListScreen._contactSectionKey,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 32,
        vertical: 36,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Visit & contact',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 700;
                  return Flex(
                    direction: isNarrow ? Axis.vertical : Axis.horizontal,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        flex: isNarrow ? 0 : 1,
                        child: Wrap(
                          spacing: 40,
                          runSpacing: 16,
                          children: const [
                            _ContactColumn(
                              title: 'Parish office',
                              lines: [
                                'Holy Parish Church',
                                '123 Parish Street, City, Country',
                              ],
                            ),
                            _ContactColumn(
                              title: 'Get in touch',
                              lines: [
                                'Email: parish@example.com',
                                'Phone: (000) 123-4567',
                              ],
                            ),
                            _ContactColumn(
                              title: 'Office hours',
                              lines: [
                                'Mon–Fri, 9:00 AM – 5:00 PM',
                                'Closed on public holidays',
                              ],
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: isNarrow ? 0 : 40,
                        height: isNarrow ? 24 : 0,
                      ),
                      Expanded(
                        flex: isNarrow ? 0 : 1,
                        child: _buildContactFormCard(context, theme),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '© 2026 Holy Parish. All rights reserved.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  void _openDetails(BuildContext context, String id) {
    Navigator.of(context).pushNamed('/announcements/$id');
  }

  void _scrollToSection(GlobalKey key) {
    final context = key.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOut,
      alignment: 0.1,
    );
  }

  Widget _buildContactFormCard(BuildContext context, ThemeData theme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.18),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.4)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Form(
            key: _contactFormKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Send us a message',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Questions, intentions, or ministry inquiries — we’d love to hear from you.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Full name'),
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'Email address'),
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) {
                      return 'Please enter your email';
                    }
                    if (!text.contains('@')) {
                      return 'Please enter a valid email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _messageController,
                  decoration: const InputDecoration(
                    labelText: 'Message',
                    alignLabelWithHint: true,
                  ),
                  maxLines: 4,
                  textInputAction: TextInputAction.newline,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a message';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    onPressed: _isSendingContact
                        ? null
                        : () async {
                            final form = _contactFormKey.currentState;
                            if (form == null || !form.validate()) return;
                            setState(() {
                              _isSendingContact = true;
                            });
                            try {
                              // Simulate send delay; hook up to backend/email later.
                              await Future<void>.delayed(
                                const Duration(seconds: 1),
                              );
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Message sent. Thank you for reaching out!',
                                  ),
                                ),
                              );
                              _nameController.clear();
                              _emailController.clear();
                              _messageController.clear();
                            } finally {
                              if (mounted) {
                                setState(() {
                                  _isSendingContact = false;
                                });
                              }
                            }
                          },
                    icon: _isSendingContact
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                theme.colorScheme.onPrimary,
                              ),
                            ),
                          )
                        : const Icon(Icons.send_rounded, size: 18),
                    label: Text(
                      _isSendingContact ? 'Sending...' : 'Send message',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GoldParticlesPainter extends CustomPainter {
  _GoldParticlesPainter({required Listenable repaint})
    : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFD4AF37).withValues(alpha: 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);

    final centers = <Offset>[
      Offset(size.width * 0.2, size.height * 0.28),
      Offset(size.width * 0.78, size.height * 0.22),
      Offset(size.width * 0.62, size.height * 0.72),
      Offset(size.width * 0.34, size.height * 0.8),
    ];

    for (final c in centers) {
      canvas.drawCircle(c, 26, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GoldParticlesPainter oldDelegate) => true;
}

class _ContactColumn extends StatelessWidget {
  const _ContactColumn({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 180),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          for (final line in lines)
            Text(line, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
