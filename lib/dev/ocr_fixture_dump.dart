import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../services/ocr_image_pick.dart';
import '../services/ocr_service.dart';
import '../services/register_ocr_scan_helper.dart';

String buildFixtureJson({
  required String image,
  required String recordType,
  required String page,
  required List<OcrLineBox> cells,
  required String flatText,
}) {
  final map = {
    'image': image,
    'recordType': recordType,
    'page': page,
    'capturedWith': 'mlkit-latin',
    'flatText': flatText,
    'cells': cells.map((c) => c.toJson()).toList(),
  };
  return const JsonEncoder.withIndent('  ').convert(map);
}

/// Debug-only screen: pick a register image, run ML Kit, dump fixture JSON.
class OcrFixtureDumpPage extends StatefulWidget {
  const OcrFixtureDumpPage({super.key});

  @override
  State<OcrFixtureDumpPage> createState() => _OcrFixtureDumpPageState();
}

class _OcrFixtureDumpPageState extends State<OcrFixtureDumpPage> {
  String _recordType = 'baptism';
  String _page = 'left';
  String? _json;
  bool _busy = false;

  Future<void> _capture() async {
    setState(() => _busy = true);
    try {
      final files = await OcrImagePick.pickRegisterPages(
        context,
        allowMultiple: false,
        includeCamera: ocrSupportsCamera,
      );
      if (files.isEmpty) return;
      final xfile = files.first;
      final result =
          await OcrService.instance.recognizeText(File(xfile.path));
      final cells = RegisterOcrScanHelper.linesFromBlocks(result.blocks);
      final json = buildFixtureJson(
        image: xfile.name,
        recordType: _recordType,
        page: _page,
        cells: cells,
        flatText: result.text,
      );

      final dir = await getApplicationDocumentsDirectory();
      final out = File('${dir.path}/${xfile.name}.ocr.json');
      await out.writeAsString(json);
      await Clipboard.setData(ClipboardData(text: json));
      debugPrint('OCR FIXTURE (${xfile.name}):\n$json');
      if (mounted) setState(() => _json = json);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('OCR Fixture Dump (debug)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    value: _recordType,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(
                          value: 'baptism', child: Text('baptism')),
                      DropdownMenuItem(
                          value: 'marriage', child: Text('marriage')),
                    ],
                    onChanged: (v) =>
                        setState(() => _recordType = v ?? 'baptism'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<String>(
                    value: _page,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: 'left', child: Text('left')),
                      DropdownMenuItem(value: 'right', child: Text('right')),
                    ],
                    onChanged: (v) => setState(() => _page = v ?? 'left'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _capture,
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Pick image & dump fixture JSON'),
            ),
            const SizedBox(height: 12),
            if (_json != null)
              Expanded(
                child: SingleChildScrollView(
                  child: SelectableText(
                    _json!,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
