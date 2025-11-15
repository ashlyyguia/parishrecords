import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:universal_html/html.dart' as html;

class ExportService {
  static Future<String> _defaultPath(String filename) async {
    if (kIsWeb) return filename;
    final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    return '${dir.path}/$filename';
  }

  static Future<void> exportJson(String filename, List<Map<String, dynamic>> data) async {
    final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
    if (kIsWeb) {
      final bytes = utf8.encode(jsonStr);
      final blob = html.Blob([bytes], 'application/json');
      final url = html.Url.createObjectUrlFromBlob(blob);
      (html.AnchorElement(href: url)
            ..setAttribute('download', filename))
          .click();
      html.Url.revokeObjectUrl(url);
    } else {
      final path = await _defaultPath(filename);
      final file = File(path);
      await file.writeAsString(jsonStr);
    }
  }

  static Future<void> exportCsv(String filename, List<List<dynamic>> rows) async {
    final csv = const ListToCsvConverter().convert(rows);
    if (kIsWeb) {
      final bytes = utf8.encode(csv);
      final blob = html.Blob([bytes], 'text/csv');
      final url = html.Url.createObjectUrlFromBlob(blob);
      (html.AnchorElement(href: url)
            ..setAttribute('download', filename))
          .click();
      html.Url.revokeObjectUrl(url);
    } else {
      final path = await _defaultPath(filename);
      final file = File(path);
      await file.writeAsString(csv);
    }
  }
}
