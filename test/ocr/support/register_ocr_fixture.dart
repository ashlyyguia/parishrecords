import 'dart:convert';
import 'dart:io';

import 'package:parishrecord/services/register_ocr_scan_helper.dart';
import 'package:parishrecord/models/register_ocr_entry.dart';

class RegisterOcrFixture {
  RegisterOcrFixture({
    required this.image,
    required this.recordType,
    required this.page,
    required this.flatText,
    required this.cells,
  });

  final String image;
  final String recordType;
  final String page;
  final String flatText;
  final List<OcrLineBox> cells;

  factory RegisterOcrFixture.fromJson(Map<String, dynamic> json) {
    return RegisterOcrFixture(
      image: json['image'] as String? ?? '',
      recordType: json['recordType'] as String? ?? 'baptism',
      page: json['page'] as String? ?? 'left',
      flatText: json['flatText'] as String? ?? '',
      cells: (json['cells'] as List<dynamic>)
          .map((c) => OcrLineBox.fromJson(Map<String, dynamic>.from(c as Map)))
          .toList(),
    );
  }
}

const _fixtureDir = 'test/ocr/fixtures';

RegisterOcrFixture loadFixture(String name) {
  final file = File('$_fixtureDir/$name.json');
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return RegisterOcrFixture.fromJson(json);
}

List<Map<String, String>> loadExpected(String name) {
  final file = File('$_fixtureDir/$name.expected.json');
  final list = jsonDecode(file.readAsStringSync()) as List<dynamic>;
  return list
      .map((e) => (e as Map).map(
            (k, v) => MapEntry(k.toString(), (v ?? '').toString()),
          ))
      .toList();
}

Map<String, String> entryToFieldMap(RegisterOcrEntry e) => {
      'lineNo': e.lineNo ?? '',
      'name': e.name,
      'date': e.baptismDateText,
      'placeAndBirthDate': e.placeAndBirthDate,
      'parents': e.parents,
      'residentsOf': e.residentsOf,
      'minister': e.minister,
      'sponsors': e.sponsors,
    };
