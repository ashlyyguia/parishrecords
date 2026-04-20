import 'package:flutter/material.dart';
import 'landing_common.dart';

class AboutSection extends StatefulWidget {
  const AboutSection({super.key});

  @override
  State<AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<AboutSection> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final List<_AboutTab> _tabs = const [
    _AboutTab('Intro', Icons.church_outlined),
    _AboutTab('History', Icons.history_edu),
    _AboutTab('Clergy & Staff', Icons.people_outline),
    _AboutTab('Gallery', Icons.photo_library_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isCompact = size.width < 900;
    final topPadding = MediaQuery.of(context).padding.top + 80;

    return LandingCommon.diagonalBackground(
      child: Container(
        padding: EdgeInsets.fromLTRB(
          isCompact ? 24 : 48,
          topPadding + (isCompact ? 24 : 48),
          isCompact ? 24 : 48,
          48,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Text(
                  'About Holy Rosary Parish',
                  style: LandingCommon.titleStyle(fontSize: isCompact ? 32 : 42),
                ),
                const SizedBox(height: 8),
                Text(
                  '"Serving Oroquieta City with faith, service, and community since 1952."',
                  style: LandingCommon.bodyStyle(
                    fontSize: isCompact ? 14 : 16,
                    color: Colors.grey.shade600,
                  ).copyWith(fontStyle: FontStyle.italic),
                ),
                const SizedBox(height: 32),
                
                // Tab Bar
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: isCompact,
                    indicator: BoxDecoration(
                      color: LandingCommon.primary,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: LandingCommon.primary.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.grey.shade600,
                    dividerColor: Colors.transparent,
                    labelStyle: LandingCommon.bodyStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    unselectedLabelStyle: LandingCommon.bodyStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    tabs: [
                      for (final tab in _tabs)
                        Tab(
                          height: 48,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(tab.icon, size: 20),
                              const SizedBox(width: 8),
                              Text(tab.label),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                
                // Tab Content
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: const [
                      _IntroTab(),
                      _HistoryTab(),
                      _StaffTab(),
                      _GalleryTab(),
                    ],
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

class _AboutTab {
  final String label;
  final IconData icon;
  const _AboutTab(this.label, this.icon);
}

// ==========================================
// Intro Tab
// ==========================================
class _IntroTab extends StatelessWidget {
  const _IntroTab();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isCompact = size.width < 900;

    if (isCompact) {
      return ListView(
        children: [
          AspectRatio(aspectRatio: 16 / 10, child: LandingCommon.churchImageCard()),
          const SizedBox(height: 32),
          _buildTextContent(center: false),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          flex: 6,
          child: AspectRatio(aspectRatio: 16 / 10, child: LandingCommon.churchImageCard()),
        ),
        const SizedBox(width: 48),
        Expanded(flex: 5, child: _buildTextContent()),
      ],
    );
  }

  Widget _buildTextContent({bool center = false}) {
    return Column(
      crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Welcome to\nHoly Rosary Parish',
          textAlign: center ? TextAlign.center : TextAlign.start,
          style: LandingCommon.titleStyle(fontSize: 32),
        ),
        const SizedBox(height: 24),
        Text(
          'Our parish is a vibrant community of faith located in the heart of Oroquieta City. We welcome all who seek spiritual growth, sacramental grace, and meaningful fellowship.',
          textAlign: center ? TextAlign.center : TextAlign.start,
          style: LandingCommon.bodyStyle(fontSize: 16),
        ),
        const SizedBox(height: 16),
        Text(
          'Join us for Mass, participate in our ministries, and become part of our growing parish family.',
          textAlign: center ? TextAlign.center : TextAlign.start,
          style: LandingCommon.bodyStyle(fontSize: 16),
        ),
      ],
    );
  }
}

// ==========================================
// History Tab
// ==========================================
class _HistoryTab extends StatelessWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isCompact = size.width < 900;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Holy Rosary Parish was established in 1952 to serve the growing Catholic community in Oroquieta City. What began as a small chapel has grown into a vibrant parish dedicated to spiritual growth, sacramental service, and community outreach.',
          style: LandingCommon.bodyStyle(fontSize: 15),
        ),
        const SizedBox(height: 16),
        Text(
          'Over the decades, the parish has expanded its ministries, improved its facilities, and embraced modern solutions to better serve the parishioners.',
          style: LandingCommon.bodyStyle(fontSize: 15),
        ),
        const SizedBox(height: 32),
        Text('Key Milestones', style: LandingCommon.titleStyle(fontSize: 24)),
        const SizedBox(height: 16),
        _MilestoneItem(year: '1952', text: 'Parish officially founded.'),
        _MilestoneItem(year: '1988', text: 'Major church renovation completed.'),
        _MilestoneItem(year: '2005', text: 'Parish community hall inaugurated.'),
        _MilestoneItem(year: '2026', text: 'Launch of Parish Operational Management System.'),
      ],
    );

    if (isCompact) {
      return ListView(
        children: [
          AspectRatio(aspectRatio: 16 / 10, child: LandingCommon.churchImageCard()),
          const SizedBox(height: 32),
          content,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 6,
          child: AspectRatio(aspectRatio: 16 / 10, child: LandingCommon.churchImageCard()),
        ),
        const SizedBox(width: 48),
        Expanded(flex: 5, child: SingleChildScrollView(child: content)),
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: LandingCommon.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              year,
              style: LandingCommon.bodyStyle(fontSize: 14, fontWeight: FontWeight.w700, color: LandingCommon.primary),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(text, style: LandingCommon.bodyStyle(fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// Staff Tab
// ==========================================
class _StaffTab extends StatelessWidget {
  const _StaffTab();

  static const _staff = [
    _StaffMember(
      name: 'Rev. Fr. Juan D. Santos',
      role: 'Parish Priest',
      description: 'Fr. Santos has served Holy Rosary Parish since 2018. He oversees spiritual leadership, sacramental administration, and parish development programs.',
    ),
    _StaffMember(
      name: 'Rev. Fr. Michael P. Reyes',
      role: 'Assistant Parish Priest',
      description: 'Fr. Reyes assists in daily Masses, confession schedules, and youth ministry programs while supporting parish outreach initiatives.',
    ),
    _StaffMember(
      name: 'Ms. Maria L. Cruz',
      role: 'Parish Secretary',
      description: 'Responsible for record management, certificate processing, and parish office operations.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 900;
        if (isCompact) {
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _staff.length,
            separatorBuilder: (context, index) => const SizedBox(width: 16),
            itemBuilder: (context, index) => SizedBox(width: 300, child: _StaffCard(member: _staff[index])),
          );
        }
        return Row(
          children: _staff.map((member) {
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _StaffCard(member: member),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _StaffMember {
  final String name;
  final String role;
  final String description;
  const _StaffMember({required this.name, required this.role, required this.description});
}

class _StaffCard extends StatelessWidget {
  final _StaffMember member;
  const _StaffCard({required this.member});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            height: 100,
            decoration: BoxDecoration(
              color: LandingCommon.primary.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                children: [
                  Transform.translate(
                    offset: const Offset(0, -40),
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(color: Colors.white, width: 4),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(Icons.person, size: 40, color: Colors.grey.shade400),
                    ),
                  ),
                  Transform.translate(
                    offset: const Offset(0, -20),
                    child: Column(
                      children: [
                        Text(
                          member.name,
                          textAlign: TextAlign.center,
                          style: LandingCommon.titleStyle(fontSize: 18),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: LandingCommon.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            member.role,
                            style: LandingCommon.bodyStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: LandingCommon.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Text(
                        member.description,
                        textAlign: TextAlign.center,
                        style: LandingCommon.bodyStyle(fontSize: 14, color: Colors.grey.shade600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// Gallery Tab
// ==========================================
class _GalleryTab extends StatelessWidget {
  const _GalleryTab();

  static const _galleryItems = [
    _GalleryItem(image: 'assets/images/hero_parish.png', title: 'Church Exterior', subtitle: 'Fiesta Celebration'),
    _GalleryItem(image: 'assets/images/hero_parish.png', title: 'Sunday Mass Gathering', subtitle: ''),
    _GalleryItem(image: 'assets/images/hero_parish.png', title: 'Youth Ministry', subtitle: 'Outreach Program'),
    _GalleryItem(image: 'assets/images/hero_parish.png', title: 'Parish Community', subtitle: 'Feeding Activity'),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 800;
        if (isCompact) {
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _galleryItems.length,
            separatorBuilder: (context, index) => const SizedBox(width: 16),
            itemBuilder: (context, index) => SizedBox(
              width: 260,
              child: _GalleryCard(item: _galleryItems[index]),
            ),
          );
        }
        return GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 16 / 12,
            crossAxisSpacing: 24,
            mainAxisSpacing: 24,
          ),
          itemCount: _galleryItems.length,
          itemBuilder: (context, index) => _GalleryCard(item: _galleryItems[index]),
        );
      },
    );
  }
}

class _GalleryItem {
  final String image;
  final String title;
  final String subtitle;
  const _GalleryItem({required this.image, required this.title, required this.subtitle});
}

class _GalleryCard extends StatelessWidget {
  final _GalleryItem item;
  const _GalleryCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: Image.asset(
                item.image,
                fit: BoxFit.cover,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: LandingCommon.bodyStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.subtitle,
                    style: LandingCommon.bodyStyle(fontSize: 13, color: Colors.grey.shade600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
