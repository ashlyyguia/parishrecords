import 'package:pdf/pdf.dart';

import '../../models/record.dart';

/// Certificates print on half an A4 sheet, portrait: A5, 148 x 210 mm.
final certificatePageFormat = PdfPageFormat.a5;

/// One blank on a certificate form: where its printed underline runs, as
/// fractions of the form's width (x0..x1) and height (y, the line itself).
/// Text is set just above the line, inside x0..x1, and shrunk to fit.
class CertificateSlot {
  final double x0;
  final double x1;
  final double y;

  const CertificateSlot(this.x0, this.x1, this.y);
}

/// A printed choice on a form (e.g. "Mr." in "Mr./Ms./Mx."), as fractions of
/// the form's width and height; the chosen one is circled.
class CertificateMark {
  final double x0;
  final double y0;
  final double x1;
  final double y1;

  const CertificateMark(this.x0, this.y0, this.x1, this.y1);
}

/// A parish certificate form: the scanned blank as the page background and
/// where each value goes on it.
///
/// The positions were measured from the blank forms' own printed underlines
/// (assets/images/certificates/*.jpg), so the filled-in values sit on the
/// lines both on screen and in the exported PDF.
class CertificateLayout {
  final String background;
  final Map<String, CertificateSlot> slots;

  /// Printed choices that can be circled, by the value that selects them.
  final Map<String, CertificateMark> marks;

  /// The baptismal form has three sponsor lines; the others have one.
  int get sponsorLines =>
      ['sponsor1', 'sponsor2', 'sponsor3'].where(slots.containsKey).length;

  const CertificateLayout(this.background, this.slots, {this.marks = const {}});

  static CertificateLayout of(RecordType type) {
    switch (type) {
      case RecordType.baptism:
        return _baptism;
      case RecordType.confirmation:
        return _confirmation;
      case RecordType.marriage:
        return _marriage;
      case RecordType.funeral:
        return _funeral;
      case RecordType.goodMoral:
        return _goodMoral;
      case RecordType.noRecord:
        return _noRecord;
    }
  }

  // Measured on the 843 x 1264 px blank form.
  static const _baptism =
      CertificateLayout('assets/images/certificates/baptism.jpg', {
        'name': CertificateSlot(0.2705, 0.8814, 0.3133),
        'childOf': CertificateSlot(0.2693, 0.8814, 0.3457),
        'and': CertificateSlot(0.2847, 0.8802, 0.3797),
        'bornIn': CertificateSlot(0.2705, 0.8814, 0.4146),
        'birthDay': CertificateSlot(0.2135, 0.2894, 0.4509),
        'birthMonth': CertificateSlot(0.3938, 0.7378, 0.4494),
        'birthYear': CertificateSlot(0.7722, 0.8814, 0.4502),
        'sacDay': CertificateSlot(0.2159, 0.3013, 0.5522),
        'sacMonth': CertificateSlot(0.3998, 0.7378, 0.5514),
        'sacYear': CertificateSlot(0.7722, 0.8814, 0.5514),
        'minister': CertificateSlot(0.3108, 0.8826, 0.6337),
        'sponsor1': CertificateSlot(0.4093, 0.8814, 0.6685),
        'sponsor2': CertificateSlot(0.2847, 0.8814, 0.7025),
        'sponsor3': CertificateSlot(0.2847, 0.8826, 0.7350),
        'dated': CertificateSlot(0.1684, 0.4069, 0.8172),
        'page': CertificateSlot(0.1696, 0.4069, 0.8497),
        'volume': CertificateSlot(0.1708, 0.4069, 0.8837),
        'series': CertificateSlot(0.1684, 0.4069, 0.9161),
        'priest': CertificateSlot(0.5018, 0.9193, 0.8734),
      });

  // Measured on the 832 x 1252 px blank form.
  static const _confirmation =
      CertificateLayout('assets/images/certificates/confirmation.jpg', {
        'name': CertificateSlot(0.2728, 0.9447, 0.3762),
        'childOf': CertificateSlot(0.2728, 0.9447, 0.4161),
        'and': CertificateSlot(0.2728, 0.9447, 0.4513),
        'bornIn': CertificateSlot(0.2728, 0.9447, 0.4904),
        'birthDay': CertificateSlot(0.2031, 0.3353, 0.5304),
        'birthMonth': CertificateSlot(0.4339, 0.7368, 0.5304),
        'birthYear': CertificateSlot(0.7596, 0.9159, 0.5304),
        'sacDay': CertificateSlot(0.2031, 0.3365, 0.6390),
        'sacMonth': CertificateSlot(0.4339, 0.7368, 0.6390),
        'sacYear': CertificateSlot(0.7596, 0.9159, 0.6390),
        'minister': CertificateSlot(0.2728, 0.9447, 0.7372),
        'sponsor1': CertificateSlot(0.3510, 0.9447, 0.7947),
        'dated': CertificateSlot(0.2320, 0.4724, 0.9185),
        'page': CertificateSlot(0.2320, 0.4736, 0.9449),
        'volume': CertificateSlot(0.2320, 0.4724, 0.9712),
        'series': CertificateSlot(0.2308, 0.4724, 0.9976),
        'priest': CertificateSlot(0.5877, 0.9447, 0.9744),
      });

  // Measured on the 848 x 1263 px blank form.
  static const _funeral =
      CertificateLayout('assets/images/certificates/funeral.jpg', {
        'name': CertificateSlot(0.2689, 0.8821, 0.3230),
        'childOf': CertificateSlot(0.2700, 0.8821, 0.3563),
        'and': CertificateSlot(0.2689, 0.8821, 0.3911),
        'bornIn': CertificateSlot(0.2689, 0.8821, 0.4260),
        'birthDay': CertificateSlot(0.2099, 0.2901, 0.4616),
        'birthMonth': CertificateSlot(0.3962, 0.7370, 0.4592),
        'birthYear': CertificateSlot(0.7700, 0.8821, 0.4616),
        'sacDay': CertificateSlot(0.2158, 0.3314, 0.5463),
        'sacMonth': CertificateSlot(0.4340, 0.7087, 0.5463),
        'sacYear': CertificateSlot(0.7347, 0.8785, 0.5463),
        'minister': CertificateSlot(0.2830, 0.9021, 0.6255),
        'sponsor1': CertificateSlot(0.3573, 0.9009, 0.6841),
        'dated': CertificateSlot(0.2453, 0.4646, 0.8599),
        'page': CertificateSlot(0.2453, 0.4646, 0.8836),
        'volume': CertificateSlot(0.2453, 0.4646, 0.9066),
        'series': CertificateSlot(0.2453, 0.4646, 0.9303),
        'priest': CertificateSlot(0.5719, 0.8986, 0.9089),
      });

  // Measured on the 848 x 1263 px blank form.
  static const _marriage =
      CertificateLayout('assets/images/certificates/marriage.jpg', {
        'name': CertificateSlot(0.2689, 0.8821, 0.3230),
        'childOf': CertificateSlot(0.2700, 0.8821, 0.3563),
        'and': CertificateSlot(0.2689, 0.8821, 0.3911),
        'bornIn': CertificateSlot(0.2689, 0.8821, 0.4260),
        'birthDay': CertificateSlot(0.2099, 0.2901, 0.4616),
        'birthMonth': CertificateSlot(0.3962, 0.7370, 0.4592),
        'birthYear': CertificateSlot(0.7700, 0.8821, 0.4616),
        'sacDay': CertificateSlot(0.2158, 0.3314, 0.5463),
        'sacMonth': CertificateSlot(0.4340, 0.7087, 0.5463),
        'sacYear': CertificateSlot(0.7347, 0.8785, 0.5463),
        'minister': CertificateSlot(0.2830, 0.9021, 0.6255),
        'sponsor1': CertificateSlot(0.3573, 0.9009, 0.6841),
        'dated': CertificateSlot(0.2453, 0.4646, 0.8599),
        'page': CertificateSlot(0.2453, 0.4646, 0.8836),
        'volume': CertificateSlot(0.2453, 0.4646, 0.9066),
        'series': CertificateSlot(0.2453, 0.4646, 0.9303),
        'priest': CertificateSlot(0.5719, 0.8986, 0.9089),
      });

  // Measured on the 843 x 1264 px blank form. It has no date line, so the
  // issue date is set in the space under "as appears from the Records of
  // this Church" ('dated' carries its own "Dated:" label).
  static const _goodMoral = CertificateLayout(
    'assets/images/certificates/good_moral.jpg',
    {
      'name': CertificateSlot(0.3215, 0.8837, 0.3481),
      'residentOf': CertificateSlot(0.3013, 0.8837, 0.3829),
      'personOf': CertificateSlot(0.3132, 0.8837, 0.4177),
      'knownAs': CertificateSlot(0.4140, 0.8837, 0.5229),
      'fitFor': CertificateSlot(0.5611, 0.8837, 0.5578),
      'fitFor2': CertificateSlot(0.1186, 0.8802, 0.5926),
      'dated': CertificateSlot(0.1186, 0.4982, 0.8228),
      'priest': CertificateSlot(0.5018, 0.9205, 0.8734),
    },
    marks: {
      'Mr.': CertificateMark(0.1151, 0.3291, 0.1767, 0.3576),
      'Ms.': CertificateMark(0.1839, 0.3291, 0.2467, 0.3576),
      'Mx.': CertificateMark(0.2515, 0.3291, 0.3132, 0.3576),
    },
  );

  // Measured on the 843 x 1264 px blank form. Like the Good Moral form it has
  // no date line, so 'dated' sits under "as appears from the Records of this
  // Church" with its own "Dated:" label.
  static const _noRecord = CertificateLayout(
    'assets/images/certificates/no_record.jpg',
    {
      'name': CertificateSlot(0.3238, 0.8837, 0.4233),
      'residentOf': CertificateSlot(0.3060, 0.8826, 0.4589),
      'dated': CertificateSlot(0.1186, 0.4982, 0.8228),
      'priest': CertificateSlot(0.5018, 0.9158, 0.8734),
    },
    marks: {
      'Mr.': CertificateMark(0.1151, 0.4019, 0.1767, 0.4304),
      'Ms.': CertificateMark(0.1839, 0.4019, 0.2467, 0.4304),
      'Mx.': CertificateMark(0.2515, 0.4019, 0.3132, 0.4304),
    },
  );
}
