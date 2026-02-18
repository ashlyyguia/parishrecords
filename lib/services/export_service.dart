// ignore_for_file: deprecated_member_use

import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:universal_html/html.dart' as html;
import 'package:pdf/widgets.dart' as pw;

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

  static Future<void> exportPdf(
    String filename,
    List<Map<String, dynamic>> data, {
    String? title,
    String? subtitle,
  }) async {
    final doc = pw.Document();

    final headers = <String>{};
    for (final m in data) {
      headers.addAll(m.keys.map((e) => e.toString()));
    }
    final cols = headers.toList();
    final rows = data
        .map((m) => cols.map((k) => m[k]?.toString() ?? '').toList())
        .toList();

    doc.addPage(
      pw.MultiPage(
        build: (context) {
          return [
            pw.Text(
              title ?? 'Parish Records Report',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            if (subtitle != null) ...[
              pw.SizedBox(height: 4),
              pw.Text(subtitle, style: pw.TextStyle(fontSize: 12)),
            ],
            pw.SizedBox(height: 16),
            if (data.isEmpty)
              pw.Text('No records for selected filters.')
            else
              pw.Table.fromTextArray(
                headers: cols,
                data: rows,
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                cellStyle: const pw.TextStyle(fontSize: 10),
              ),
          ];
        },
      ),
    );

    final bytes = await doc.save();

    if (kIsWeb) {
      final blob = html.Blob([bytes], 'application/pdf');
      final url = html.Url.createObjectUrlFromBlob(blob);
      (html.AnchorElement(
        href: url,
      )..setAttribute('download', filename)).click();
      html.Url.revokeObjectUrl(url);
    } else {
      final path = await _defaultPath(filename);
      final file = File(path);
      await file.writeAsBytes(bytes);
    }
  }
}
