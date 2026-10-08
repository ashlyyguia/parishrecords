// ignore_for_file: deprecated_member_use

import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:universal_html/html.dart' as html;
import 'package:printing/printing.dart';

import '../utils/firestore_date.dart';
import 'report_pdf_service.dart';

class ExportService {
  static Future<String> _defaultPath(String filename) async {
    if (kIsWeb) return filename;
    final dir =
        await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    return '${dir.path}/$filename';
  }

  static Future<void> exportJson(
    String filename,
    List<Map<String, dynamic>> data,
  ) async {
    final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
    if (kIsWeb) {
      final bytes = utf8.encode(jsonStr);
      final blob = html.Blob([bytes], 'application/json');
      final url = html.Url.createObjectUrlFromBlob(blob);
      (html.AnchorElement(
        href: url,
      )..setAttribute('download', filename)).click();
      html.Url.revokeObjectUrl(url);
    } else {
      final path = await _defaultPath(filename);
      final file = File(path);
      await file.writeAsString(jsonStr);
    }
  }

  static Future<void> exportCsv(
    String filename,
    List<List<dynamic>> rows,
  ) async {
    final csv = const ListToCsvConverter().convert(rows);
    if (kIsWeb) {
      final bytes = utf8.encode(csv);
      final blob = html.Blob([bytes], 'text/csv');
      final url = html.Url.createObjectUrlFromBlob(blob);
      (html.AnchorElement(
        href: url,
      )..setAttribute('download', filename)).click();
      html.Url.revokeObjectUrl(url);
    } else {
      final path = await _defaultPath(filename);
      final file = File(path);
      await file.writeAsString(csv);
    }
  }

  /// Saves ready-made PDF bytes: a browser download on web, the share sheet elsewhere.
  static Future<void> savePdfBytes(Uint8List bytes, String filename) async {
    if (kIsWeb) {
      final blob = html.Blob([bytes], 'application/pdf');
      final url = html.Url.createObjectUrlFromBlob(blob);
      (html.AnchorElement(href: url)..setAttribute('download', filename)).click();
      html.Url.revokeObjectUrl(url);
    } else {
      await Printing.sharePdf(bytes: bytes, filename: filename);
    }
  }

  /// Generic list-to-PDF export, styled with the app theme via ReportPdfService.
  /// Column headers are prettified ("created_at" -> "Created at") and dates
  /// are formatted; for purpose-built reports call ReportPdfService directly.
  static Future<void> exportPdf(
    String filename,
    List<Map<String, dynamic>> data, {
    String? title,
    String? subtitle,
  }) async {
    final keys = <String>{for (final m in data) ...m.keys.map((e) => e.toString())}.toList();
    String cell(dynamic v) {
      if (v == null) return '';
      final looksLikeDate = v is! String || (v.length >= 10 && DateTime.tryParse(v) != null);
      final dt = looksLikeDate ? parseFirestoreDate(v) : null;
      if (dt != null) return ReportPdfService.shortDate(dt);
      final t = v.toString();
      return t.length > 80 ? '${t.substring(0, 77)}...' : t;
    }

    final bytes = await ReportPdfService.tableReport(
      title: title ?? 'Parish Records Report',
      period: subtitle ?? '',
      headers: [for (final k in keys) ReportPdfService.titleCase(k)],
      rows: [for (final m in data) [for (final k in keys) cell(m[k])]],
      landscape: keys.length > 5,
      tiles: [['Records', '${data.length}']],
      generatedBy: ReportPdfService.currentUserLabel(),
    );
    await savePdfBytes(bytes, filename);
  }
}
