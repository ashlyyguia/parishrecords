import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../services/ocr_image_pick.dart';
import '../services/ocr_service.dart';
import '../services/register_ocr_image_preprocess.dart';
import '../services/register_ocr_scan_helper.dart';

String buildFixtureJson({
  required String image,
  required String recordType,
  required String page,
  required List<OcrLineBox> cells,
  required String flatText,
  String capturedWith = 'mlkit-latin',
}) {
  final map = {
    'image': image,
    'recordType': recordType,
    'page': page,
    'capturedWith': capturedWith,
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
  // Best on-device config from measured evidence: ~2000px (picker default) and
  // no preprocessing gave the most ML Kit cells; full-res and aggressive
  // enhance both reduced recognition. Toggles remain for experimentation.
  bool _fullRes = false;
  bool _preprocess = false;
  String? _status;

  Future<void> _capture() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final files = await OcrImagePick.pickRegisterPages(
        context,
        allowMultiple: false,
        includeCamera: ocrSupportsCamera,
        fullResolution: _fullRes,
      );
      if (files.isEmpty) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final xfile = files.first;
      final original = await xfile.readAsBytes();

      // Diagnostic: OCR the raw picked bytes so we can compare raw vs enhanced.
      final rawResult = await OcrService.instance.recognizeBytes(original);
      final rawCells =
          RegisterOcrScanHelper.linesFromBlocks(rawResult.blocks);

      var chosenCells = rawCells;
      var chosenText = rawResult.text;
      var enhancedInfo = '';

      if (_preprocess) {
        // Gentle: grayscale + mild contrast only. The default (1.35 contrast +
        // brightness + gamma + sharpen) blew faint register ink out to white.
        final enhanced = await RegisterOcrImagePreprocess.enhanceWithOptions(
          original,
          contrast: 1.12,
          brightness: 0.0,
          sharpen: false,
        );
        final enhResult = await OcrService.instance.recognizeBytes(enhanced);
        final enhCells =
            RegisterOcrScanHelper.linesFromBlocks(enhResult.blocks);
        chosenCells = enhCells;
        chosenText = enhResult.text;
        enhancedInfo =
            '; enhanced ${(enhanced.length / 1024).round()}KB → '
            '${enhCells.length} cells';
      }

      final json = buildFixtureJson(
        image: xfile.name,
        recordType: _recordType,
        page: _page,
        cells: chosenCells,
        flatText: chosenText,
        capturedWith: _preprocess ? 'mlkit-latin+enhance' : 'mlkit-latin',
      );

      if (!kIsWeb) {
        final dir = await getApplicationDocumentsDirectory();
        final out = File('${dir.path}/${xfile.name}.ocr.json');
        await out.writeAsString(json);
      }
      await Clipboard.setData(ClipboardData(text: json));

      final status = 'picked ${(original.length / 1024).round()}KB → '
          'raw ${rawCells.length} cells$enhancedInfo';
      debugPrint('OCR FIXTURE (${xfile.name}): $status');
      if (mounted) {
        setState(() {
          _json = json;
          _status = status;
        });
      }
    } catch (e, st) {
      debugPrint('OCR dump error: $e\n$st');
      if (mounted) setState(() => _status = 'ERROR: $e');
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
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Full resolution (no downscale)'),
              value: _fullRes,
              onChanged: _busy ? null : (v) => setState(() => _fullRes = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Preprocess before OCR'),
              subtitle: const Text('grayscale + sharpen + contrast'),
              value: _preprocess,
              onChanged: _busy ? null : (v) => setState(() => _preprocess = v),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _capture,
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Pick image & dump fixture JSON'),
            ),
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _status!,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: _status!.startsWith('ERROR')
                            ? Theme.of(context).colorScheme.error
                            : null,
                      ),
                ),
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
