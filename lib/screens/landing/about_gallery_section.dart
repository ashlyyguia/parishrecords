// ignore_for_file: unnecessary_underscores

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'landing_common.dart';

class AboutGallerySection extends StatelessWidget {
  const AboutGallerySection({super.key});

  static const _galleryItems = [
    _GalleryItem(
      image: 'assets/images/hero_parish.png',
      title: 'Church Exterior During',
      subtitle: 'Fiesta Celebration',
    ),
    _GalleryItem(
      image: 'assets/images/hero_parish.png',
      title: 'Sunday Mass Gathering',
      subtitle: '',
    ),
    _GalleryItem(
      image: 'assets/images/hero_parish.png',
      title: 'Youth Ministry',
      subtitle: 'Outreach Program',
    ),
    _GalleryItem(
      image: 'assets/images/hero_parish.png',
      title: 'Parish Community',
      subtitle: 'Feeding Activity',
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
                      final isCompact = constraints.maxWidth < 800;
                      if (isCompact) {
                        return ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _galleryItems.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 16),
                          itemBuilder: (_, index) => SizedBox(
                            width: 200,
                            child: _GalleryCard(item: _galleryItems[index]),
                          ),
                        );
                      }
                      return Row(
                        children: _galleryItems.map((item) {
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              child: _GalleryCard(item: item),
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

class _GalleryItem {
  final String image;
  final String title;
  final String subtitle;

  const _GalleryItem({
    required this.image,
    required this.title,
    required this.subtitle,
  });
}

class _GalleryCard extends StatelessWidget {
  final _GalleryItem item;

  const _GalleryCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: LandingCommon.primary, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.asset(
                item.image,
                fit: BoxFit.cover,
                width: double.infinity,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          item.title,
          style: GoogleFonts.merriweather(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            fontStyle: FontStyle.italic,
            color: Colors.black,
          ),
        ),
        if (item.subtitle.isNotEmpty)
          Text(
            item.subtitle,
            style: GoogleFonts.merriweather(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              fontStyle: FontStyle.italic,
              color: Colors.black,
            ),
          ),
      ],
    );
  }
}
