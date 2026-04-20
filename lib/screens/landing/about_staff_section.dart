// ignore_for_file: unnecessary_underscores

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'landing_common.dart';

class AboutStaffSection extends StatelessWidget {
  const AboutStaffSection({super.key});

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
    return LandingCommon.diagonalBackground(
      child: Container(
        padding: const EdgeInsets.fromLTRB(28, 92, 28, 28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ABOUT HOLY ROSARY PARISH',
                  style: GoogleFonts.merriweather(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    fontStyle: FontStyle.italic,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '"Serving Oroquieta City with faith, service, and community since 1952."',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    color: Colors.black.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 40),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isCompact = constraints.maxWidth < 900;
                      if (isCompact) {
                        return ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _staff.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 16),
                          itemBuilder: (_, index) => SizedBox(
                            width: 280,
                            child: _StaffCard(member: _staff[index]),
                          ),
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
        color: LandingCommon.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Purple top accent
          Container(
            height: 8,
            decoration: BoxDecoration(
              color: LandingCommon.primary,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Avatar placeholder
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: LandingCommon.primary, width: 2),
                      color: Colors.white,
                    ),
                    child: Icon(
                      Icons.person,
                      size: 50,
                      color: LandingCommon.primary.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    member.name,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.merriweather(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      fontStyle: FontStyle.italic,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    member.role,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.black.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Text(
                        member.description,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          height: 1.5,
                          color: Colors.black.withValues(alpha: 0.75),
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
