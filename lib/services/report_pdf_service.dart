// Shared PDF export templates for the whole app, styled with the app theme
// (AppColors "Sky Azure" palette + Roboto). Every PDF report/export goes through here.
//
// - financialOverview: A4 portrait, summary tiles + breakdown tables.
// - donations:         A4 landscape, one row per donation.
// - userActivity:      A4 portrait, accounts by role.
// - tableReport:       any list export (fees, ledger, records register).
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../app/app_colors.dart';
import '../utils/donation_display.dart';
import '../utils/firestore_date.dart';

class ReportPdfService {
  ReportPdfService._();

  static const _parish = 'HOLY ROSARY PARISH';
  static const _parishLine = 'Oroquieta City, Misamis Occidental · Archdiocese of Ozamis';

  // Palette: taken from the app theme (lib/app/app_colors.dart).
  static PdfColor _c(Color c) => PdfColor.fromInt(c.toARGB32());
  static final _navy = _c(AppColors.primaryDark); // headings, totals
  static final _blue = _c(AppColors.primary); // table headers, bars, accents
  static final _accent = _c(AppColors.accent); // gradient stop
  static final _ink = _c(AppColors.ink);
  static final _muted = _c(AppColors.slate500);
  static final _line = _c(AppColors.border);
  static final _zebra = _c(AppColors.scaffold);
  static final _tile = _c(AppColors.tint);
  static final _tileEdge = _c(AppColors.tintStrong);
  static final _green = _c(AppColors.successDark);
  static final _amber = _c(AppColors.warningDark);

  // ---------------------------------------------------------------------------
  // Shared pieces
  // ---------------------------------------------------------------------------

  /// Fonts with the peso sign. Falls back to the built-in font (and "PHP")
  /// when the fonts cannot be downloaded, so export never fails offline.
  static Future<_Kit> _kit() async {
    // Roboto, the app's font, is bundled (assets/fonts) so the peso sign and
    // dashes render offline. Google's Roboto is a second choice; built-in last.
    pw.Font? base, bold;
    try {
      base = pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
      bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
    } catch (_) {
      try {
        base = await PdfGoogleFonts.robotoRegular();
        bold = await PdfGoogleFonts.robotoBold();
      } catch (_) {
        base = bold = null;
      }
    }
    pw.MemoryImage? logo;
    try {
      final bytes = await rootBundle.load('assets/icons/app_icon.png');
      // The app icon is large; a 128px copy keeps each PDF small.
      final decoded = img.decodeImage(bytes.buffer.asUint8List());
      logo = decoded == null
          ? null
          : pw.MemoryImage(Uint8List.fromList(img.encodePng(img.copyResize(decoded, width: 128))));
    } catch (_) {}
    final theme = base != null && bold != null
        ? pw.ThemeData.withFont(base: base, bold: bold)
        : pw.ThemeData.base();
    return _Kit(theme: theme, logo: logo, peso: base != null ? '\u20B1' : 'PHP ');
  }

  static String _money(_Kit k, num v) =>
      '${k.peso}${NumberFormat('#,##0.00').format(v)}';

  static final _date = DateFormat('MMM d, yyyy');
  static final _stamp = DateFormat('MMMM d, yyyy · h:mm a');

  static pw.PageTheme _page(_Kit k, PdfPageFormat format) => pw.PageTheme(
    pageFormat: format,
    margin: const pw.EdgeInsets.fromLTRB(36, 30, 36, 30),
    theme: k.theme,
  );

  static pw.Widget _header(_Kit k, String title) => pw.Column(children: [
    // Brand gradient strip (AppColors.brandGradient).
    pw.Container(
      height: 4,
      margin: const pw.EdgeInsets.only(bottom: 8),
      decoration: pw.BoxDecoration(
        borderRadius: pw.BorderRadius.circular(2),
        gradient: pw.LinearGradient(colors: [_blue, _accent]),
      ),
    ),
    pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 8),
    margin: const pw.EdgeInsets.only(bottom: 14),
    decoration: pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: _tileEdge, width: 1)),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (k.logo != null) ...[
          pw.Image(k.logo!, width: 30, height: 30),
          pw.SizedBox(width: 8),
        ],
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(_parish, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _navy, letterSpacing: 0.8)),
              pw.Text(_parishLine, style: pw.TextStyle(fontSize: 7.5, color: _muted)),
            ],
          ),
        ),
        pw.Text(title, style: pw.TextStyle(fontSize: 9, color: _muted)),
      ],
    ),
  ),
  ]);

  static pw.Widget _footer(pw.Context ctx) => pw.Container(
    margin: const pw.EdgeInsets.only(top: 10),
    padding: const pw.EdgeInsets.only(top: 6),
    decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _line, width: 0.6))),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text('ParishRecord · For parish administration use only', style: pw.TextStyle(fontSize: 7, color: _muted)),
        pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: pw.TextStyle(fontSize: 7, color: _muted)),
      ],
    ),
  );

  static pw.Widget _titleBlock(String title, String period, String generatedBy) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(title, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: _ink)),
      pw.SizedBox(height: 3),
      pw.Text(period, style: pw.TextStyle(fontSize: 10, color: _blue, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 2),
      pw.Text('Generated ${_stamp.format(DateTime.now())}${generatedBy.isNotEmpty ? ' by $generatedBy' : ''}',
          style: pw.TextStyle(fontSize: 8, color: _muted)),
      pw.SizedBox(height: 14),
    ],
  );

  static pw.Widget _tiles(List<List<String>> items) => pw.Row(
    children: [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) pw.SizedBox(width: 8),
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.fromLTRB(10, 8, 10, 9),
            decoration: pw.BoxDecoration(color: _tile, borderRadius: pw.BorderRadius.circular(8), border: pw.Border.all(color: _tileEdge, width: 0.8)),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(items[i][0].toUpperCase(), style: pw.TextStyle(fontSize: 6.5, color: _muted, letterSpacing: 0.6)),
                pw.SizedBox(height: 3),
                pw.Text(items[i][1], style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _navy)),
                if (items[i].length > 2) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(items[i][2], style: pw.TextStyle(fontSize: 7, color: _muted)),
                ],
              ],
            ),
          ),
        ),
      ],
    ],
  );

  static pw.Widget _section(String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 16, bottom: 6),
    child: pw.Text(text, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _navy)),
  );

  static pw.Widget _table({
    required List<String> headers,
    required List<List<String>> rows,
    Map<int, pw.TableColumnWidth>? widths,
    Set<int> right = const {},
    Set<int> center = const {},
    double fontSize = 8.5,
  }) {
    final align = <int, pw.Alignment>{
      for (var i = 0; i < headers.length; i++)
        i: right.contains(i)
            ? pw.Alignment.centerRight
            : center.contains(i)
                ? pw.Alignment.center
                : pw.Alignment.centerLeft,
    };
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      headerCount: 1,
      columnWidths: widths,
      border: pw.TableBorder(horizontalInside: pw.BorderSide(color: _line, width: 0.4), bottom: pw.BorderSide(color: _line, width: 0.6)),
      headerDecoration: pw.BoxDecoration(color: _blue),
      headerStyle: pw.TextStyle(color: PdfColors.white, fontSize: fontSize, fontWeight: pw.FontWeight.bold),
      headerAlignments: align,
      cellAlignments: align,
      cellStyle: pw.TextStyle(fontSize: fontSize, color: _ink),
      oddRowDecoration: pw.BoxDecoration(color: _zebra),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4.5),
      headerPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    );
  }

  /// A thin bar showing [share] (0..1) for breakdown tables.
  static pw.Widget _bar(double share) {
    final pct = (share * 100).round().clamp(0, 100);
    return pw.Row(children: [
      if (pct > 0) pw.Expanded(flex: pct, child: pw.Container(height: 5, color: _blue)),
      if (pct < 100) pw.Expanded(flex: 100 - pct, child: pw.Container(height: 5, color: _tileEdge)),
    ]);
  }

  static pw.Widget _breakdown(_Kit k, String title, Map<String, _Agg> data, double total) {
    final entries = data.entries.toList()..sort((a, b) => b.value.amount.compareTo(a.value.amount));
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      _section(title),
      pw.Table(
        columnWidths: const {
          0: pw.FlexColumnWidth(3),
          1: pw.FlexColumnWidth(1.3),
          2: pw.FlexColumnWidth(2),
          3: pw.FlexColumnWidth(2.6),
        },
        border: pw.TableBorder(horizontalInside: pw.BorderSide(color: _line, width: 0.4), bottom: pw.BorderSide(color: _line, width: 0.6)),
        children: [
          pw.TableRow(
            decoration: pw.BoxDecoration(color: _blue),
            children: [
              for (final h in ['Category', 'Count', 'Amount', 'Share of total'])
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                  child: pw.Text(h, textAlign: h == 'Amount' || h == 'Count' ? pw.TextAlign.right : pw.TextAlign.left,
                      style: pw.TextStyle(color: PdfColors.white, fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                ),
            ],
          ),
          for (var i = 0; i < entries.length; i++)
            pw.TableRow(
              decoration: i.isOdd ? pw.BoxDecoration(color: _zebra) : null,
              verticalAlignment: pw.TableCellVerticalAlignment.middle,
              children: [
                _cell(entries[i].key),
                _cell('${entries[i].value.count}', right: true),
                _cell(_money(k, entries[i].value.amount), right: true),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4.5),
                  child: pw.Row(children: [
                    pw.Expanded(child: _bar(total > 0 ? entries[i].value.amount / total : 0)),
                    pw.SizedBox(width: 6),
                    pw.SizedBox(
                      width: 30,
                      child: pw.Text('${total > 0 ? (entries[i].value.amount / total * 100).toStringAsFixed(1) : '0.0'}%',
                          textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8, color: _muted)),
                    ),
                  ]),
                ),
              ],
            ),
          pw.TableRow(children: [
            _cell('Total', bold: true),
            _cell('${data.values.fold<int>(0, (s, a) => s + a.count)}', right: true, bold: true),
            _cell(_money(k, total), right: true, bold: true),
            _cell(''),
          ]),
        ],
      ),
    ]);
  }

  static pw.Widget _cell(String t, {bool right = false, bool bold = false, PdfColor? color}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4.5),
    child: pw.Text(t,
        textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
        style: pw.TextStyle(fontSize: 8.5, color: color ?? _ink, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
  );

  static pw.Widget _signatures(List<List<String>> people) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 34),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
      children: [
        for (final p in people)
          pw.SizedBox(
            width: 170,
            child: pw.Column(children: [
              pw.Align(alignment: pw.Alignment.centerLeft, child: pw.Text(p[0], style: pw.TextStyle(fontSize: 8, color: _muted))),
              pw.SizedBox(height: 26),
              pw.Container(height: 0.8, color: _ink),
              pw.SizedBox(height: 3),
              pw.Text(p[1], style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
            ]),
          ),
      ],
    ),
  );

  static bool _isFee(Map<String, dynamic> d) =>
      (d['campaign'] ?? '').toString().trim().toLowerCase() == 'certificate';

  static String _donor(Map<String, dynamic> d) {
    if (d['anonymous'] == true) return 'Anonymous';
    final n = (d['donor_name'] ?? '').toString().trim();
    return n.isEmpty ? 'Anonymous' : n;
  }

  static double _amt(Map<String, dynamic> d) => (d['amount'] as num?)?.toDouble() ?? 0;

  // ---------------------------------------------------------------------------
  // Financial Overview (portrait)
  // ---------------------------------------------------------------------------

  static Future<Uint8List> financialOverview({
    required List<Map<String, dynamic>> donations,
    required DateTime from,
    required DateTime to,
    String generatedBy = '',
  }) async {
    final k = await _kit();
    double total = 0, gifts = 0, fees = 0, rec = 0, pend = 0;
    int nGifts = 0, nFees = 0, nRec = 0, nPend = 0;
    final byMethod = <String, _Agg>{};
    final byFund = <String, _Agg>{};
    final byWeek = <DateTime, _Agg>{};
    for (final d in donations) {
      final a = _amt(d);
      total += a;
      if (_isFee(d)) { fees += a; nFees++; } else { gifts += a; nGifts++; }
      if (d['reconciled'] == true) { rec += a; nRec++; } else { pend += a; nPend++; }
      byMethod.putIfAbsent(formatPaymentMethod(donationPaymentMethodId(d)), () => _Agg()).add(a);
      final fund = _isFee(d)
          ? 'Certificate fees${(d['certificate_type'] ?? '').toString().isNotEmpty ? ' (${d['certificate_type']})' : ''}'
          : donationTypeLabel(d);
      byFund.putIfAbsent(fund, () => _Agg()).add(a);
      final dt = parseFirestoreDate(d['created_at']);
      if (dt != null) {
        final monday = DateTime(dt.year, dt.month, dt.day).subtract(Duration(days: dt.weekday - 1));
        byWeek.putIfAbsent(monday, () => _Agg()).add(a);
      }
    }
    final avg = donations.isEmpty ? 0 : total / donations.length;
    final weeks = byWeek.keys.toList()..sort();

    final doc = pw.Document(title: 'Financial Overview Report', author: 'Holy Rosary Parish');
    doc.addPage(pw.MultiPage(
      pageTheme: _page(k, PdfPageFormat.a4),
      header: (_) => _header(k, 'Financial Overview Report'),
      footer: _footer,
      build: (_) => [
        _titleBlock('Financial Overview', '${_date.format(from)} – ${_date.format(to)}', generatedBy),
        _tiles([
          ['Total collected', _money(k, total), '${donations.length} transactions'],
          ['Donations', _money(k, gifts), '$nGifts gifts'],
          ['Certificate fees', _money(k, fees), '$nFees payments'],
          ['Average amount', _money(k, avg), 'Per transaction'],
        ]),
        if (donations.isEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 24),
            child: pw.Text('No collections were recorded in this period.', style: pw.TextStyle(color: _muted)),
          )
        else ...[
          _breakdown(k, 'Collections by payment method', byMethod, total),
          _breakdown(k, 'Collections by fund', byFund, total),
          _section('Collections by week'),
          _table(
            headers: ['Week starting', 'Transactions', 'Amount'],
            rows: [for (final w in weeks) [_date.format(w), '${byWeek[w]!.count}', _money(k, byWeek[w]!.amount)]],
            widths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(1.5), 2: pw.FlexColumnWidth(2)},
            right: {1, 2},
          ),
          // Container (not a bare Column) so the heading and boxes never split across pages.
          pw.Container(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            _section('Reconciliation status'),
            pw.Row(children: [
              pw.Expanded(child: _statusBox('Reconciled', _money(k, rec), '$nRec transactions matched to bank or cash records', _green)),
              pw.SizedBox(width: 8),
              pw.Expanded(child: _statusBox('Pending reconciliation', _money(k, pend), '$nPend transactions still to be verified', _amber)),
            ]),
          ])),
        ],
        _signatures([
          ['Prepared by:', 'Finance Officer'],
          ['Noted by:', 'Parish Priest'],
        ]),
      ],
    ));
    return doc.save();
  }

  static pw.Widget _statusBox(String label, String value, String note, PdfColor color) => pw.Container(
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      border: pw.Border(left: pw.BorderSide(color: color, width: 3)),
      color: _zebra,
    ),
    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text(label, style: pw.TextStyle(fontSize: 8, color: color, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 2),
      pw.Text(value, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _ink)),
      pw.Text(note, style: pw.TextStyle(fontSize: 7, color: _muted)),
    ]),
  );

  // ---------------------------------------------------------------------------
  // Donations Report (landscape)
  // ---------------------------------------------------------------------------

  static Future<Uint8List> donations({
    required List<Map<String, dynamic>> donations,
    required String periodLabel,
    String generatedBy = '',
  }) async {
    final k = await _kit();
    final sorted = [...donations]
      ..sort((a, b) => (parseFirestoreDate(b['created_at']) ?? DateTime(0)).compareTo(parseFirestoreDate(a['created_at']) ?? DateTime(0)));
    double total = 0, online = 0, walkIn = 0, pending = 0;
    for (final d in sorted) {
      final a = _amt(d);
      total += a;
      if (isOnlineDonation(d)) { online += a; } else { walkIn += a; }
      if (d['reconciled'] != true) pending += a;
    }
    final rows = <List<String>>[];
    for (var i = 0; i < sorted.length; i++) {
      final d = sorted[i];
      final dt = parseFirestoreDate(d['created_at']);
      rows.add([
        '${i + 1}',
        dt != null ? _date.format(dt) : '—',
        _donor(d),
        donationTypeLabel(d),
        formatPaymentMethod(donationPaymentMethodId(d)),
        isOnlineDonation(d) ? 'Online' : 'Walk-in',
        d['amount_pending'] == true ? 'Awaiting amount' : (d['reconciled'] == true ? 'Reconciled' : 'Pending'),
        d['amount_pending'] == true ? '—' : _money(k, _amt(d)),
      ]);
    }

    final doc = pw.Document(title: 'Donations Report', author: 'Holy Rosary Parish');
    doc.addPage(pw.MultiPage(
      pageTheme: _page(k, PdfPageFormat.a4.landscape),
      header: (_) => _header(k, 'Donations Report'),
      footer: _footer,
      build: (_) => [
        _titleBlock('Donations Report', periodLabel, generatedBy),
        _tiles([
          ['Total donations', _money(k, total), '${sorted.length} records'],
          ['Online (e-wallet)', _money(k, online), 'GCash, Maya, GoTyme'],
          ['Walk-in (cash)', _money(k, walkIn), 'Recorded at the parish office'],
          ['Pending reconciliation', _money(k, pending), 'Not yet verified by Finance'],
        ]),
        pw.SizedBox(height: 14),
        if (rows.isEmpty)
          pw.Text('No donations found.', style: pw.TextStyle(color: _muted))
        else
          _table(
            headers: ['#', 'Date', 'Donor', 'Fund / Purpose', 'Method', 'Channel', 'Status', 'Amount'],
            rows: rows,
            widths: const {
              0: pw.FixedColumnWidth(26),
              1: pw.FixedColumnWidth(70),
              2: pw.FlexColumnWidth(3),
              3: pw.FlexColumnWidth(2.6),
              4: pw.FixedColumnWidth(58),
              5: pw.FixedColumnWidth(52),
              6: pw.FixedColumnWidth(78),
              7: pw.FixedColumnWidth(78),
            },
            right: {0, 7},
          ),
        pw.Container(
          alignment: pw.Alignment.centerRight,
          padding: const pw.EdgeInsets.only(top: 8, right: 6),
          child: pw.Text('Grand total: ${_money(k, total)}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _navy)),
        ),
        _signatures([
          ['Prepared by:', 'Finance Officer'],
          ['Verified by:', 'Parish Administrator'],
        ]),
      ],
    ));
    return doc.save();
  }

  // ---------------------------------------------------------------------------
  // User Activity Summary (portrait)
  // ---------------------------------------------------------------------------

  static Future<Uint8List> userActivity({
    required List<Map<String, dynamic>> users,
    String generatedBy = '',
  }) async {
    final k = await _kit();
    final byRole = <String, int>{};
    for (final u in users) {
      final r = _roleLabel(u['role']);
      byRole[r] = (byRole[r] ?? 0) + 1;
    }
    final now = DateTime.now();
    final active30 = users.where((u) {
      final l = parseFirestoreDate(u['lastLogin'] ?? u['last_login']);
      return l != null && now.difference(l).inDays <= 30;
    }).length;
    final sorted = [...users]
      ..sort((a, b) {
        final r = _roleRank(a['role']).compareTo(_roleRank(b['role']));
        return r != 0 ? r : _name(a).toLowerCase().compareTo(_name(b).toLowerCase());
      });

    final doc = pw.Document(title: 'User Activity Summary', author: 'Holy Rosary Parish');
    doc.addPage(pw.MultiPage(
      pageTheme: _page(k, PdfPageFormat.a4),
      header: (_) => _header(k, 'User Activity Summary'),
      footer: _footer,
      build: (_) => [
        _titleBlock('User Activity Summary', 'All system accounts as of ${_date.format(now)}', generatedBy),
        _tiles([
          ['Total accounts', '${users.length}'],
          ['Active in last 30 days', '$active30'],
          ['Staff & finance', '${(byRole['Staff'] ?? 0) + (byRole['Finance'] ?? 0)}'],
          ['Parishioners', '${byRole['Parishioner'] ?? 0}'],
        ]),
        _section('Accounts'),
        _table(
          headers: ['Name', 'Email', 'Role', 'Verified', 'Registered', 'Last sign-in'],
          rows: [
            for (final u in sorted)
              [
                _name(u),
                (u['email'] ?? '').toString(),
                _roleLabel(u['role']),
                (u['verificationCodeVerified'] == true || u['emailVerified'] == true) ? 'Yes' : 'No',
                _fmt(u['createdAt'] ?? u['created_at']),
                _fmt(u['lastLogin'] ?? u['last_login']),
              ],
          ],
          widths: const {
            0: pw.FlexColumnWidth(2.2),
            1: pw.FlexColumnWidth(3.2),
            2: pw.FlexColumnWidth(1.4),
            3: pw.FlexColumnWidth(1.1),
            4: pw.FlexColumnWidth(1.7),
            5: pw.FlexColumnWidth(1.7),
          },
          center: {3},
          fontSize: 8,
        ),
        _section('Accounts by role'),
        _table(
          headers: ['Role', 'Accounts'],
          rows: [for (final e in byRole.entries) [e.key, '${e.value}']],
          widths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(1)},
          right: {1},
        ),
      ],
    ));
    return doc.save();
  }

  // ---------------------------------------------------------------------------
  // Generic list export (certificate fees, ledgers, records register, backups)
  // ---------------------------------------------------------------------------

  /// Formats a peso amount for table cells, e.g. ₱1,250.00.
  static String peso(num v) => '\u20B1${NumberFormat('#,##0.00').format(v)}';

  /// A themed one-table report: header, title block, optional summary tiles,
  /// a striped table, an optional total line, and optional signature lines.
  static Future<Uint8List> tableReport({
    required String title,
    required String period,
    required List<String> headers,
    required List<List<String>> rows,
    Map<int, pw.TableColumnWidth>? widths,
    Set<int> right = const {},
    Set<int> center = const {},
    List<List<String>> tiles = const [],
    String? totalLine,
    bool landscape = false,
    List<List<String>> signatures = const [],
    String generatedBy = '',
    String emptyText = 'No records found.',
  }) async {
    final k = await _kit();
    // If the bundled font failed to load, the base font has no peso sign.
    String fix(String t) => k.peso == '\u20B1' ? t : t.replaceAll('\u20B1', 'PHP ');
    final doc = pw.Document(title: title, author: 'Holy Rosary Parish');
    doc.addPage(pw.MultiPage(
      pageTheme: _page(k, landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4),
      header: (_) => _header(k, title),
      footer: _footer,
      build: (_) => [
        _titleBlock(title, period, generatedBy),
        if (tiles.isNotEmpty) ...[
          _tiles([for (final t in tiles) [for (final x in t) fix(x)]]),
          pw.SizedBox(height: 14),
        ],
        if (rows.isEmpty)
          pw.Text(emptyText, style: pw.TextStyle(color: _muted))
        else
          _table(
            headers: headers,
            rows: [for (final r in rows) [for (final c in r) fix(c)]],
            widths: widths,
            right: right,
            center: center,
            fontSize: landscape ? 8.5 : 8,
          ),
        if (totalLine != null)
          pw.Container(
            alignment: pw.Alignment.centerRight,
            padding: const pw.EdgeInsets.only(top: 8, right: 6),
            child: pw.Text(fix(totalLine), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _navy)),
          ),
        if (signatures.isNotEmpty) _signatures(signatures),
      ],
    ));
    return doc.save();
  }

  // ---------------------------------------------------------------------------
  // Donor statements (Finance Reports page)
  // ---------------------------------------------------------------------------

  static Future<Uint8List> donorStatements({
    required List<Map<String, dynamic>> donations,
    required DateTime from,
    required DateTime to,
    String generatedBy = '',
  }) {
    final gifts = donations.where((d) => !_isFee(d)).toList();
    final byDonor = <String, _Agg>{};
    final last = <String, DateTime>{};
    for (final d in gifts) {
      final name = _donor(d);
      byDonor.putIfAbsent(name, () => _Agg()).add(_amt(d));
      final dt = parseFirestoreDate(d['created_at']);
      if (dt != null && (last[name] == null || dt.isAfter(last[name]!))) last[name] = dt;
    }
    final entries = byDonor.entries.toList()..sort((a, b) => b.value.amount.compareTo(a.value.amount));
    final total = gifts.fold<double>(0, (t, d) => t + _amt(d));
    return tableReport(
      title: 'Donor Statements',
      period: '${_date.format(from)} \u2013 ${_date.format(to)}',
      headers: const ['#', 'Donor', 'Gifts', 'Total given', 'Last gift'],
      rows: [
        for (var i = 0; i < entries.length; i++)
          [
            '${i + 1}',
            entries[i].key,
            '${entries[i].value.count}',
            peso(entries[i].value.amount),
            last[entries[i].key] != null ? _date.format(last[entries[i].key]!) : '\u2014',
          ],
      ],
      widths: const {0: pw.FixedColumnWidth(26), 2: pw.FixedColumnWidth(48), 3: pw.FixedColumnWidth(90), 4: pw.FixedColumnWidth(80)},
      right: const {0, 2, 3},
      tiles: [
        ['Total donations', peso(total), '${gifts.length} gifts'],
        ['Donors', '${entries.length}'],
        ['Average per donor', peso(entries.isEmpty ? 0 : total / entries.length)],
      ],
      totalLine: 'Grand total: ${peso(total)}',
      signatures: const [['Prepared by:', 'Finance Officer'], ['Noted by:', 'Parish Priest']],
      generatedBy: generatedBy,
    );
  }

  // ---------------------------------------------------------------------------
  // Small helpers shared by the export screens
  // ---------------------------------------------------------------------------

  /// "Oct 8, 2026" from a Firestore Timestamp, DateTime, or ISO string.
  static String shortDate(dynamic v) => _fmt(v);

  /// Donor/payer name, or "Anonymous".
  static String donorName(Map<String, dynamic> d) => _donor(d);

  /// "Sep 1, 2026 – Oct 8, 2026", "From …", "Until …", or "All records".
  static String periodLabel(DateTime? from, DateTime? to) {
    if (from == null && to == null) return 'All records';
    if (from != null && to != null) return '${_date.format(from)} \u2013 ${_date.format(to)}';
    return from != null ? 'From ${_date.format(from)}' : 'Until ${_date.format(to!)}';
  }

  /// "funeral" -> "Funeral", "in_review" -> "In review".
  static String titleCase(String v) {
    final t = v.replaceAll('_', ' ').trim();
    return t.isEmpty ? '\u2014' : t[0].toUpperCase() + t.substring(1).toLowerCase();
  }

  /// Name (or email) of the signed-in user, for the "Generated … by" line.
  static String currentUserLabel() {
    final u = FirebaseAuth.instance.currentUser;
    final name = u?.displayName?.trim() ?? '';
    return name.isNotEmpty ? name : (u?.email ?? '');
  }

  static String _fmt(dynamic v) {
    final d = parseFirestoreDate(v);
    return d == null ? '—' : _date.format(d);
  }

  static String _name(Map<String, dynamic> u) {
    final n = (u['displayName'] ?? u['name'] ?? '').toString().trim();
    return n.isEmpty ? (u['email'] ?? '—').toString() : n;
  }

  static String _roleLabel(dynamic r) {
    final s = (r ?? '').toString().trim().toLowerCase();
    switch (s) {
      case 'admin':
        return 'Administrator';
      case 'staff':
        return 'Staff';
      case 'finance':
        return 'Finance';
      case '':
      case 'user':
      case 'parishioner':
        return 'Parishioner';
      default:
        return s[0].toUpperCase() + s.substring(1);
    }
  }

  static int _roleRank(dynamic r) {
    const order = ['admin', 'staff', 'finance'];
    final i = order.indexOf((r ?? '').toString().toLowerCase());
    return i < 0 ? order.length : i;
  }

  // ---------------------------------------------------------------------------
  // CSV rows (clean, human-readable columns)
  // ---------------------------------------------------------------------------

  static List<List<dynamic>> donationsCsv(List<Map<String, dynamic>> donations) => [
    ['Date', 'Donor', 'Fund / Purpose', 'Method', 'Channel', 'Status', 'Amount (PHP)', 'Email', 'Phone', 'Message'],
    for (final d in donations)
      [
        _fmt(d['created_at']),
        _donor(d),
        donationTypeLabel(d),
        formatPaymentMethod(donationPaymentMethodId(d)),
        isOnlineDonation(d) ? 'Online' : 'Walk-in',
        d['reconciled'] == true ? 'Reconciled' : 'Pending',
        _amt(d).toStringAsFixed(2),
        donorEmail(d) ?? '',
        donorPhone(d) ?? '',
        (d['donor_message'] ?? '').toString(),
      ],
  ];

  static List<List<dynamic>> financialCsv(List<Map<String, dynamic>> donations, DateTime from, DateTime to) {
    final byMethod = <String, _Agg>{};
    final byFund = <String, _Agg>{};
    double total = 0;
    for (final d in donations) {
      final a = _amt(d);
      total += a;
      byMethod.putIfAbsent(formatPaymentMethod(donationPaymentMethodId(d)), () => _Agg()).add(a);
      byFund.putIfAbsent(_isFee(d) ? 'Certificate fees' : donationTypeLabel(d), () => _Agg()).add(a);
    }
    return [
      ['Financial Overview', '${_date.format(from)} to ${_date.format(to)}', ''],
      ['Total collected (PHP)', total.toStringAsFixed(2), ''],
      ['Transactions', donations.length, ''],
      [],
      ['Payment method', 'Transactions', 'Amount (PHP)'],
      for (final e in byMethod.entries) [e.key, e.value.count, e.value.amount.toStringAsFixed(2)],
      [],
      ['Fund', 'Transactions', 'Amount (PHP)'],
      for (final e in byFund.entries) [e.key, e.value.count, e.value.amount.toStringAsFixed(2)],
    ];
  }

  static List<List<dynamic>> usersCsv(List<Map<String, dynamic>> users) => [
    ['Name', 'Email', 'Role', 'Verified', 'Registered', 'Last sign-in'],
    for (final u in users)
      [
        _name(u),
        (u['email'] ?? '').toString(),
        _roleLabel(u['role']),
        (u['verificationCodeVerified'] == true || u['emailVerified'] == true) ? 'Yes' : 'No',
        _fmt(u['createdAt'] ?? u['created_at']),
        _fmt(u['lastLogin'] ?? u['last_login']),
      ],
  ];
}

class _Kit {
  _Kit({required this.theme, required this.logo, required this.peso});
  final pw.ThemeData theme;
  final pw.MemoryImage? logo;
  final String peso;
}

class _Agg {
  int count = 0;
  double amount = 0;
  void add(double a) {
    count++;
    amount += a;
  }
}
