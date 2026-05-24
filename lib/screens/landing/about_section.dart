import 'package:flutter/material.dart';
import 'landing_common.dart';

class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isCompact = size.width < 900;
    final topPadding = MediaQuery.of(context).padding.top + 80;

    return LandingCommon.diagonalBackground(
      child: SingleChildScrollView(
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
                    style: LandingCommon.titleStyle(
                      fontSize: isCompact ? 32 : 42,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '"Serving Oroquieta City with faith, service, and community since 1952."',
                    style: LandingCommon.bodyStyle(
                      fontSize: isCompact ? 14 : 16,
                      color: Colors.grey.shade600,
                    ).copyWith(fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 48),

                  // Combined About Content
                  _buildIntroSection(context, isCompact),
                  const SizedBox(height: 64),
                  _buildHistorySection(context, isCompact),
                  const SizedBox(height: 64),
                  _buildStaffSection(context, isCompact),
                  const SizedBox(height: 48),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: LandingCommon.primary, size: 28),
        const SizedBox(width: 12),
        Text(title, style: LandingCommon.titleStyle(fontSize: 24)),
      ],
    );
  }

  Widget _buildIntroSection(BuildContext context, bool isCompact) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, 'Welcome', Icons.church_outlined),
        const SizedBox(height: 24),
        if (isCompact) ...[
          AspectRatio(
            aspectRatio: 16 / 10,
            child: LandingCommon.churchImageCard(),
          ),
          const SizedBox(height: 24),
          _buildIntroContent(center: true),
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 6,
                child: AspectRatio(
                  aspectRatio: 16 / 10,
                  child: LandingCommon.churchImageCard(),
                ),
              ),
              const SizedBox(width: 48),
              Expanded(flex: 5, child: _buildIntroContent()),
            ],
          ),
      ],
    );
  }

  Widget _buildIntroContent({bool center = false}) {
    return Column(
      crossAxisAlignment: center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Welcome to Holy Rosary Parish',
          textAlign: center ? TextAlign.center : TextAlign.start,
          style: LandingCommon.titleStyle(fontSize: 28),
        ),
        const SizedBox(height: 16),
        Text(
          'Our parish is a vibrant community of faith located in the heart of Oroquieta City. We welcome all who seek spiritual growth, sacramental grace, and meaningful fellowship.',
          textAlign: center ? TextAlign.center : TextAlign.start,
          style: LandingCommon.bodyStyle(fontSize: 16),
        ),
        const SizedBox(height: 12),
        Text(
          'Join us for Mass, participate in our ministries, and become part of our growing parish family.',
          textAlign: center ? TextAlign.center : TextAlign.start,
          style: LandingCommon.bodyStyle(fontSize: 16),
        ),
      ],
    );
  }

  Widget _buildHistorySection(BuildContext context, bool isCompact) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, 'Our History', Icons.history_edu),
        const SizedBox(height: 24),
        Text(
          'Holy Rosary Parish was established in 1952 to serve the growing Catholic community in Oroquieta City. What began as a small chapel has grown into a vibrant parish dedicated to spiritual growth, sacramental service, and community outreach.',
          style: LandingCommon.bodyStyle(fontSize: 15),
        ),
        const SizedBox(height: 12),
        Text(
          'Over the decades, the parish has expanded its ministries, improved its facilities, and embraced modern solutions to better serve the parishioners.',
          style: LandingCommon.bodyStyle(fontSize: 15),
        ),
        const SizedBox(height: 24),
        Text('Key Milestones', style: LandingCommon.titleStyle(fontSize: 20)),
        const SizedBox(height: 16),
        _MilestoneItem(year: '1952', text: 'Parish officially founded.'),
        _MilestoneItem(
          year: '1988',
          text: 'Major church renovation completed.',
        ),
        _MilestoneItem(
          year: '2005',
          text: 'Parish community hall inaugurated.',
        ),
        _MilestoneItem(
          year: '2026',
          text: 'Launch of Parish Operational Management System.',
        ),
      ],
    );

    if (isCompact) {
      return Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 10,
            child: LandingCommon.churchImageCard(),
          ),
          const SizedBox(height: 24),
          content,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 6,
          child: AspectRatio(
            aspectRatio: 16 / 10,
            child: LandingCommon.churchImageCard(),
          ),
        ),
        const SizedBox(width: 48),
        Expanded(flex: 5, child: content),
      ],
    );
  }

  Widget _buildStaffSection(BuildContext context, bool isCompact) {
    const staff = [
      _StaffMember(
        name: 'Rev. Fr. Juan D. Santos',
        role: 'Parish Priest',
        description:
            'Fr. Santos has served Holy Rosary Parish since 2018. He oversees spiritual leadership, sacramental administration, and parish development programs.',
      ),
      _StaffMember(
        name: 'Rev. Fr. Michael P. Reyes',
        role: 'Assistant Parish Priest',
        description:
            'Fr. Reyes assists in daily Masses, confession schedules, and youth ministry programs while supporting parish outreach initiatives.',
      ),
      _StaffMember(
        name: 'Ms. Maria L. Cruz',
        role: 'Parish Secretary',
        description:
            'Responsible for record management, certificate processing, and parish office operations.',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, 'Clergy & Staff', Icons.people_outline),
        const SizedBox(height: 24),
        if (isCompact)
          SizedBox(
            height: 320,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: staff.length,
              separatorBuilder: (context, index) => const SizedBox(width: 16),
              itemBuilder: (context, index) =>
                  SizedBox(width: 300, child: _StaffCard(member: staff[index])),
            ),
          )
        else
          SizedBox(
            height: 320,
            child: Row(
              children: staff.map((member) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: _StaffCard(member: member),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}

// ==========================================
// Helper Classes
// ==========================================
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
              style: LandingCommon.bodyStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: LandingCommon.primary,
              ),
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

class _StaffMember {
  final String name;
  final String role;
  final String description;
  const _StaffMember({
    required this.name,
    required this.role,
    required this.description,
  });
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
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
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
                      child: Icon(
                        Icons.person,
                        size: 40,
                        color: Colors.grey.shade400,
                      ),
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
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
                        style: LandingCommon.bodyStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
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
