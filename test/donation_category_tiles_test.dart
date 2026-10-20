import 'package:flutter_test/flutter_test.dart';
import 'package:parishrecord/services/report_pdf_service.dart';

void main() {
  test('donationCategoryTiles totals each category, standard ones first', () {
    final tiles = ReportPdfService.donationCategoryTiles([
      {'campaign': 'tithes', 'amount': 100},
      {'campaign': 'Tithes', 'amount': 50},
      {'campaign': 'offering', 'amount': 250},
      {'campaign': 'general', 'amount': 100},
    ]);
    expect(tiles.map((t) => t[0]).toList(), ['Tithes', 'Offering', 'Projects', 'Outreach', 'General']);
    expect(tiles[0][1], '₱150.00');
    expect(tiles[0][2], '2 records · 30.0%');
    expect(tiles[1][2], '1 record · 50.0%');
    expect(tiles[2][1], '₱0.00');
    expect(tiles[2][2], '0 records · 0.0%');
  });
}
