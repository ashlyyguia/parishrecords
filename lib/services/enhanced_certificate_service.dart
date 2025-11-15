import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import '../models/record.dart';

class EnhancedCertificateService {
  static const String _certificateNumber = 'CERT';
  
  /// Generate a professional certificate PDF with custom templates
  static Future<File> generateCertificate({
    required Map<String, dynamic> recordData,
    required String certificateType,
    String? customTemplate,
  }) async {
    final pdf = pw.Document();
    
    // Load fonts for better typography
    final regularFont = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
    final boldFont = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
    final italicFont = await rootBundle.load('assets/fonts/Roboto-Italic.ttf');
    
    final ttfRegular = pw.Font.ttf(regularFont);
    final ttfBold = pw.Font.ttf(boldFont);
    final ttfItalic = pw.Font.ttf(italicFont);
    
    // Load parish logo if available
    Uint8List? logoBytes;
    try {
      final logoData = await rootBundle.load('assets/images/parish_logo.png');
      logoBytes = logoData.buffer.asUint8List();
    } catch (e) {
      // Logo not found, continue without it
    }
    
    // Generate certificate based on type
    switch (certificateType.toLowerCase()) {
      case 'baptism':
        await _generateBaptismCertificate(pdf, recordData, ttfRegular, ttfBold, ttfItalic, logoBytes);
        break;
      case 'marriage':
        await _generateMarriageCertificate(pdf, recordData, ttfRegular, ttfBold, ttfItalic, logoBytes);
        break;
      case 'confirmation':
        await _generateConfirmationCertificate(pdf, recordData, ttfRegular, ttfBold, ttfItalic, logoBytes);
        break;
      case 'funeral':
      case 'death':
        await _generateFuneralCertificate(pdf, recordData, ttfRegular, ttfBold, ttfItalic, logoBytes);
        break;
      default:
        await _generateGenericCertificate(pdf, recordData, ttfRegular, ttfBold, ttfItalic, logoBytes);
    }
    
    // Save PDF to device
    final directory = await getApplicationDocumentsDirectory();
    final certificateNumber = _generateCertificateNumber(certificateType);
    final fileName = '${certificateType}_certificate_${certificateNumber}.pdf';
    final file = File('${directory.path}/$fileName');
    
    await file.writeAsBytes(await pdf.save());
    return file;
  }
  
  static Future<void> _generateBaptismCertificate(
    pw.Document pdf,
    Map<String, dynamic> data,
    pw.Font regular,
    pw.Font bold,
    pw.Font italic,
    Uint8List? logo,
  ) async {
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header with logo and parish info
              _buildCertificateHeader(logo, 'CERTIFICATE OF BAPTISM', bold, regular),
              
              pw.SizedBox(height: 30),
              
              // Decorative border
              pw.Container(
                padding: const pw.EdgeInsets.all(20),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.blue800, width: 2),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // Certificate content
                    pw.Center(
                      child: pw.Text(
                        'This is to certify that',
                        style: pw.TextStyle(font: italic, fontSize: 16),
                      ),
                    ),
                    
                    pw.SizedBox(height: 15),
                    
                    pw.Center(
                      child: pw.Text(
                        data['name']?.toString().toUpperCase() ?? 'NAME NOT PROVIDED',
                        style: pw.TextStyle(font: bold, fontSize: 24, color: PdfColors.blue800),
                      ),
                    ),
                    
                    pw.SizedBox(height: 20),
                    
                    pw.Text(
                      'was baptized according to the rite of the Roman Catholic Church',
                      style: pw.TextStyle(font: regular, fontSize: 14),
                      textAlign: pw.TextAlign.center,
                    ),
                    
                    pw.SizedBox(height: 15),
                    
                    // Baptism details
                    _buildDetailRow('Date of Baptism:', _formatDate(data['date']), regular, bold),
                    _buildDetailRow('Place of Baptism:', data['place']?.toString() ?? 'Not specified', regular, bold),
                    _buildDetailRow('Parish:', data['parish']?.toString() ?? 'Not specified', regular, bold),
                    
                    // Parse additional details from notes if available
                    if (data['notes'] != null) ..._parseBaptismNotes(data['notes'], regular, bold),
                    
                    pw.SizedBox(height: 20),
                    
                    // Registry information
                    pw.Container(
                      padding: const pw.EdgeInsets.all(10),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.grey100,
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('Registry Information:', style: pw.TextStyle(font: bold, fontSize: 12)),
                          pw.SizedBox(height: 5),
                          _buildDetailRow('Registry No:', data['registryNumber']?.toString() ?? 'Not assigned', regular, regular),
                          _buildDetailRow('Book/Page/Line:', '${data['bookNumber'] ?? 'N/A'}/${data['pageNumber'] ?? 'N/A'}/${data['lineNumber'] ?? 'N/A'}', regular, regular),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              pw.Spacer(),
              
              // Footer with signatures and date
              _buildCertificateFooter(regular, italic),
            ],
          );
        },
      ),
    );
  }
  
  static Future<void> _generateMarriageCertificate(
    pw.Document pdf,
    Map<String, dynamic> data,
    pw.Font regular,
    pw.Font bold,
    pw.Font italic,
    Uint8List? logo,
  ) async {
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildCertificateHeader(logo, 'CERTIFICATE OF MARRIAGE', bold, regular),
              
              pw.SizedBox(height: 30),
              
              pw.Container(
                padding: const pw.EdgeInsets.all(20),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.pink800, width: 2),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Center(
                      child: pw.Text(
                        'This is to certify that',
                        style: pw.TextStyle(font: italic, fontSize: 16),
                      ),
                    ),
                    
                    pw.SizedBox(height: 15),
                    
                    pw.Center(
                      child: pw.Text(
                        data['name']?.toString().toUpperCase() ?? 'NAMES NOT PROVIDED',
                        style: pw.TextStyle(font: bold, fontSize: 20, color: PdfColors.pink800),
                        textAlign: pw.TextAlign.center,
                      ),
                    ),
                    
                    pw.SizedBox(height: 20),
                    
                    pw.Text(
                      'were united in Holy Matrimony according to the rite of the Roman Catholic Church',
                      style: pw.TextStyle(font: regular, fontSize: 14),
                      textAlign: pw.TextAlign.center,
                    ),
                    
                    pw.SizedBox(height: 15),
                    
                    _buildDetailRow('Date of Marriage:', _formatDate(data['date']), regular, bold),
                    _buildDetailRow('Place of Marriage:', data['place']?.toString() ?? 'Not specified', regular, bold),
                    _buildDetailRow('Parish:', data['parish']?.toString() ?? 'Not specified', regular, bold),
                    
                    if (data['notes'] != null) ..._parseMarriageNotes(data['notes'], regular, bold),
                  ],
                ),
              ),
              
              pw.Spacer(),
              _buildCertificateFooter(regular, italic),
            ],
          );
        },
      ),
    );
  }
  
  static Future<void> _generateConfirmationCertificate(
    pw.Document pdf,
    Map<String, dynamic> data,
    pw.Font regular,
    pw.Font bold,
    pw.Font italic,
    Uint8List? logo,
  ) async {
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildCertificateHeader(logo, 'CERTIFICATE OF CONFIRMATION', bold, regular),
              
              pw.SizedBox(height: 30),
              
              pw.Container(
                padding: const pw.EdgeInsets.all(20),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.green800, width: 2),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Center(
                      child: pw.Text(
                        'This is to certify that',
                        style: pw.TextStyle(font: italic, fontSize: 16),
                      ),
                    ),
                    
                    pw.SizedBox(height: 15),
                    
                    pw.Center(
                      child: pw.Text(
                        data['name']?.toString().toUpperCase() ?? 'NAME NOT PROVIDED',
                        style: pw.TextStyle(font: bold, fontSize: 24, color: PdfColors.green800),
                      ),
                    ),
                    
                    pw.SizedBox(height: 20),
                    
                    pw.Text(
                      'was confirmed according to the rite of the Roman Catholic Church',
                      style: pw.TextStyle(font: regular, fontSize: 14),
                      textAlign: pw.TextAlign.center,
                    ),
                    
                    pw.SizedBox(height: 15),
                    
                    _buildDetailRow('Date of Confirmation:', _formatDate(data['date']), regular, bold),
                    _buildDetailRow('Place of Confirmation:', data['place']?.toString() ?? 'Not specified', regular, bold),
                    _buildDetailRow('Parish:', data['parish']?.toString() ?? 'Not specified', regular, bold),
                    
                    if (data['notes'] != null) ..._parseConfirmationNotes(data['notes'], regular, bold),
                  ],
                ),
              ),
              
              pw.Spacer(),
              _buildCertificateFooter(regular, italic),
            ],
          );
        },
      ),
    );
  }
  
  static Future<void> _generateFuneralCertificate(
    pw.Document pdf,
    Map<String, dynamic> data,
    pw.Font regular,
    pw.Font bold,
    pw.Font italic,
    Uint8List? logo,
  ) async {
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildCertificateHeader(logo, 'CERTIFICATE OF FUNERAL RITES', bold, regular),
              
              pw.SizedBox(height: 30),
              
              pw.Container(
                padding: const pw.EdgeInsets.all(20),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.purple800, width: 2),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Center(
                      child: pw.Text(
                        'This is to certify that funeral rites were celebrated for',
                        style: pw.TextStyle(font: italic, fontSize: 16),
                        textAlign: pw.TextAlign.center,
                      ),
                    ),
                    
                    pw.SizedBox(height: 15),
                    
                    pw.Center(
                      child: pw.Text(
                        data['name']?.toString().toUpperCase() ?? 'NAME NOT PROVIDED',
                        style: pw.TextStyle(font: bold, fontSize: 24, color: PdfColors.purple800),
                      ),
                    ),
                    
                    pw.SizedBox(height: 20),
                    
                    pw.Text(
                      'according to the rite of the Roman Catholic Church',
                      style: pw.TextStyle(font: regular, fontSize: 14),
                      textAlign: pw.TextAlign.center,
                    ),
                    
                    pw.SizedBox(height: 15),
                    
                    _buildDetailRow('Date of Funeral:', _formatDate(data['date']), regular, bold),
                    _buildDetailRow('Place of Funeral:', data['place']?.toString() ?? 'Not specified', regular, bold),
                    _buildDetailRow('Parish:', data['parish']?.toString() ?? 'Not specified', regular, bold),
                    
                    if (data['notes'] != null) ..._parseFuneralNotes(data['notes'], regular, bold),
                  ],
                ),
              ),
              
              pw.Spacer(),
              _buildCertificateFooter(regular, italic),
            ],
          );
        },
      ),
    );
  }
  
  static Future<void> _generateGenericCertificate(
    pw.Document pdf,
    Map<String, dynamic> data,
    pw.Font regular,
    pw.Font bold,
    pw.Font italic,
    Uint8List? logo,
  ) async {
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildCertificateHeader(logo, 'PARISH CERTIFICATE', bold, regular),
              
              pw.SizedBox(height: 30),
              
              pw.Container(
                padding: const pw.EdgeInsets.all(20),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.blue800, width: 2),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Center(
                      child: pw.Text(
                        'This is to certify that',
                        style: pw.TextStyle(font: italic, fontSize: 16),
                      ),
                    ),
                    
                    pw.SizedBox(height: 15),
                    
                    pw.Center(
                      child: pw.Text(
                        data['name']?.toString().toUpperCase() ?? 'NAME NOT PROVIDED',
                        style: pw.TextStyle(font: bold, fontSize: 24, color: PdfColors.blue800),
                      ),
                    ),
                    
                    pw.SizedBox(height: 20),
                    
                    _buildDetailRow('Record Type:', data['type']?.toString() ?? 'Not specified', regular, bold),
                    _buildDetailRow('Date:', _formatDate(data['date']), regular, bold),
                    _buildDetailRow('Place:', data['place']?.toString() ?? 'Not specified', regular, bold),
                    _buildDetailRow('Parish:', data['parish']?.toString() ?? 'Not specified', regular, bold),
                    
                    if (data['notes'] != null && data['notes'].toString().isNotEmpty) ...[
                      pw.SizedBox(height: 10),
                      pw.Text('Additional Information:', style: pw.TextStyle(font: bold, fontSize: 12)),
                      pw.SizedBox(height: 5),
                      pw.Text(data['notes'].toString(), style: pw.TextStyle(font: regular, fontSize: 11)),
                    ],
                  ],
                ),
              ),
              
              pw.Spacer(),
              _buildCertificateFooter(regular, italic),
            ],
          );
        },
      ),
    );
  }
  
  // Helper methods
  static pw.Widget _buildCertificateHeader(Uint8List? logo, String title, pw.Font bold, pw.Font regular) {
    return pw.Column(
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            if (logo != null) ...[
              pw.Image(pw.MemoryImage(logo), width: 60, height: 60),
              pw.SizedBox(width: 20),
            ],
            pw.Expanded(
              child: pw.Column(
                children: [
                  pw.Text(
                    'HOLY ROSARY PARISH',
                    style: pw.TextStyle(font: bold, fontSize: 18),
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.SizedBox(height: 5),
                  pw.Text(
                    'Roman Catholic Church',
                    style: pw.TextStyle(font: regular, fontSize: 12),
                    textAlign: pw.TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
        
        pw.SizedBox(height: 20),
        
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(vertical: 10),
          decoration: const pw.BoxDecoration(
            color: PdfColors.blue800,
          ),
          child: pw.Text(
            title,
            style: pw.TextStyle(font: bold, fontSize: 16, color: PdfColors.white),
            textAlign: pw.TextAlign.center,
          ),
        ),
      ],
    );
  }
  
  static pw.Widget _buildDetailRow(String label, String value, pw.Font regular, pw.Font bold) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 120,
            child: pw.Text(label, style: pw.TextStyle(font: bold, fontSize: 12)),
          ),
          pw.Expanded(
            child: pw.Text(value, style: pw.TextStyle(font: regular, fontSize: 12)),
          ),
        ],
      ),
    );
  }
  
  static pw.Widget _buildCertificateFooter(pw.Font regular, pw.Font italic) {
    return pw.Column(
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  width: 200,
                  height: 1,
                  color: PdfColors.black,
                ),
                pw.SizedBox(height: 5),
                pw.Text('Parish Priest', style: pw.TextStyle(font: regular, fontSize: 10)),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Container(
                  width: 150,
                  height: 1,
                  color: PdfColors.black,
                ),
                pw.SizedBox(height: 5),
                pw.Text('Date Issued', style: pw.TextStyle(font: regular, fontSize: 10)),
              ],
            ),
          ],
        ),
        
        pw.SizedBox(height: 20),
        
        pw.Text(
          'Certificate issued on ${DateFormat('MMMM dd, yyyy').format(DateTime.now())}',
          style: pw.TextStyle(font: italic, fontSize: 10),
          textAlign: pw.TextAlign.center,
        ),
        
        pw.SizedBox(height: 10),
        
        pw.Text(
          'This certificate is valid only with the official parish seal.',
          style: pw.TextStyle(font: italic, fontSize: 8, color: PdfColors.grey600),
          textAlign: pw.TextAlign.center,
        ),
      ],
    );
  }
  
  // Note parsing methods
  static List<pw.Widget> _parseBaptismNotes(dynamic notes, pw.Font regular, pw.Font bold) {
    final List<pw.Widget> widgets = [];
    
    try {
      if (notes is String) {
        // Try to parse as JSON
        final Map<String, dynamic> parsedNotes = {};
        if (notes.contains('parents') || notes.contains('godparents')) {
          // Simple parsing for common fields
          if (notes.contains('parents')) {
            final parentsMatch = RegExp(r'parents["\s:]+([^"]+)', caseSensitive: false).firstMatch(notes);
            if (parentsMatch != null) {
              parsedNotes['parents'] = parentsMatch.group(1)?.trim();
            }
          }
          if (notes.contains('godparents')) {
            final godparentsMatch = RegExp(r'godparents["\s:]+([^"]+)', caseSensitive: false).firstMatch(notes);
            if (godparentsMatch != null) {
              parsedNotes['godparents'] = godparentsMatch.group(1)?.trim();
            }
          }
          if (notes.contains('minister')) {
            final ministerMatch = RegExp(r'minister["\s:]+([^"]+)', caseSensitive: false).firstMatch(notes);
            if (ministerMatch != null) {
              parsedNotes['minister'] = ministerMatch.group(1)?.trim();
            }
          }
        }
        
        if (parsedNotes.isNotEmpty) {
          widgets.add(pw.SizedBox(height: 10));
          if (parsedNotes['parents'] != null) {
            widgets.add(_buildDetailRow('Parents:', parsedNotes['parents'], regular, bold));
          }
          if (parsedNotes['godparents'] != null) {
            widgets.add(_buildDetailRow('Godparents:', parsedNotes['godparents'], regular, bold));
          }
          if (parsedNotes['minister'] != null) {
            widgets.add(_buildDetailRow('Minister:', parsedNotes['minister'], regular, bold));
          }
        }
      }
    } catch (e) {
      // If parsing fails, just show the raw notes
      widgets.add(pw.SizedBox(height: 10));
      widgets.add(_buildDetailRow('Notes:', notes.toString(), regular, bold));
    }
    
    return widgets;
  }
  
  static List<pw.Widget> _parseMarriageNotes(dynamic notes, pw.Font regular, pw.Font bold) {
    final List<pw.Widget> widgets = [];
    
    try {
      if (notes is String && notes.contains('witnesses')) {
        final witnessesMatch = RegExp(r'witnesses["\s:]+([^"]+)', caseSensitive: false).firstMatch(notes);
        if (witnessesMatch != null) {
          widgets.add(pw.SizedBox(height: 10));
          widgets.add(_buildDetailRow('Witnesses:', witnessesMatch.group(1)?.trim() ?? '', regular, bold));
        }
        
        final ministerMatch = RegExp(r'minister["\s:]+([^"]+)', caseSensitive: false).firstMatch(notes);
        if (ministerMatch != null) {
          widgets.add(_buildDetailRow('Minister:', ministerMatch.group(1)?.trim() ?? '', regular, bold));
        }
      }
    } catch (e) {
      widgets.add(pw.SizedBox(height: 10));
      widgets.add(_buildDetailRow('Notes:', notes.toString(), regular, bold));
    }
    
    return widgets;
  }
  
  static List<pw.Widget> _parseConfirmationNotes(dynamic notes, pw.Font regular, pw.Font bold) {
    final List<pw.Widget> widgets = [];
    
    try {
      if (notes is String && notes.contains('sponsor')) {
        final sponsorMatch = RegExp(r'sponsor["\s:]+([^"]+)', caseSensitive: false).firstMatch(notes);
        if (sponsorMatch != null) {
          widgets.add(pw.SizedBox(height: 10));
          widgets.add(_buildDetailRow('Sponsor:', sponsorMatch.group(1)?.trim() ?? '', regular, bold));
        }
        
        final ministerMatch = RegExp(r'minister["\s:]+([^"]+)', caseSensitive: false).firstMatch(notes);
        if (ministerMatch != null) {
          widgets.add(_buildDetailRow('Minister:', ministerMatch.group(1)?.trim() ?? '', regular, bold));
        }
      }
    } catch (e) {
      widgets.add(pw.SizedBox(height: 10));
      widgets.add(_buildDetailRow('Notes:', notes.toString(), regular, bold));
    }
    
    return widgets;
  }
  
  static List<pw.Widget> _parseFuneralNotes(dynamic notes, pw.Font regular, pw.Font bold) {
    final List<pw.Widget> widgets = [];
    
    try {
      if (notes is String) {
        widgets.add(pw.SizedBox(height: 10));
        widgets.add(_buildDetailRow('Additional Information:', notes, regular, bold));
      }
    } catch (e) {
      // Handle error silently
    }
    
    return widgets;
  }
  
  static String _formatDate(dynamic date) {
    if (date == null) return 'Not specified';
    
    try {
      if (date is String) {
        final parsedDate = DateTime.tryParse(date);
        if (parsedDate != null) {
          return DateFormat('MMMM dd, yyyy').format(parsedDate);
        }
      } else if (date is DateTime) {
        return DateFormat('MMMM dd, yyyy').format(date);
      }
    } catch (e) {
      // Return original string if parsing fails
    }
    
    return date.toString();
  }
  
  static String _generateCertificateNumber(String type) {
    final now = DateTime.now();
    final year = now.year;
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final timestamp = now.millisecondsSinceEpoch.toString().substring(8);
    
    final typeCode = type.substring(0, 1).toUpperCase();
    return '$_certificateNumber-$year$month$day-$typeCode$timestamp';
  }
}
