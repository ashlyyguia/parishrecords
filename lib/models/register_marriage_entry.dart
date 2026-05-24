/// One party line on a parish marriage register (groom or bride).
class MarriagePartyInfo {
  MarriagePartyInfo({
    this.name = '',
    this.legalStatus = '',
    this.actualAddress = '',
    this.datesPlaceOfBirth = '',
    this.datesPlaceOfBaptism = '',
    this.parents = '',
    this.sponsors = '',
  });

  String name;
  String legalStatus;
  String actualAddress;
  String datesPlaceOfBirth;
  String datesPlaceOfBaptism;
  String parents;
  String sponsors;

  bool get hasData => name.trim().isNotEmpty;
}

/// One marriage register entry = groom row + bride row + shared fields.
class RegisterMarriageEntry {
  RegisterMarriageEntry({
    required this.id,
    this.lineNo,
    MarriagePartyInfo? groom,
    MarriagePartyInfo? bride,
    this.dateOfMarriage = '',
    this.minister = '',
    this.licenseNumber = '',
    this.observations = '',
    this.selected = true,
  })  : groom = groom ?? MarriagePartyInfo(),
        bride = bride ?? MarriagePartyInfo();

  final String id;
  String? lineNo;
  MarriagePartyInfo groom;
  MarriagePartyInfo bride;
  String dateOfMarriage;
  String minister;
  String licenseNumber;
  String observations;
  bool selected;

  /// Display name for record list (groom & bride).
  String get recordDisplayName {
    final g = groom.name.trim();
    final b = bride.name.trim();
    if (g.isNotEmpty && b.isNotEmpty) return '$g & $b';
    return g.isNotEmpty ? g : b;
  }

  String get primaryAddress {
    final g = groom.actualAddress.trim();
    if (g.isNotEmpty) return g;
    return bride.actualAddress.trim();
  }

  bool get isReadyToSave =>
      groom.name.trim().length >= 2 || bride.name.trim().length >= 2;

  RegisterMarriageEntry copyWith({String? id}) {
    return RegisterMarriageEntry(
      id: id ?? this.id,
      lineNo: lineNo,
      groom: MarriagePartyInfo(
        name: groom.name,
        legalStatus: groom.legalStatus,
        actualAddress: groom.actualAddress,
        datesPlaceOfBirth: groom.datesPlaceOfBirth,
        datesPlaceOfBaptism: groom.datesPlaceOfBaptism,
        parents: groom.parents,
        sponsors: groom.sponsors,
      ),
      bride: MarriagePartyInfo(
        name: bride.name,
        legalStatus: bride.legalStatus,
        actualAddress: bride.actualAddress,
        datesPlaceOfBirth: bride.datesPlaceOfBirth,
        datesPlaceOfBaptism: bride.datesPlaceOfBaptism,
        parents: bride.parents,
        sponsors: bride.sponsors,
      ),
      dateOfMarriage: dateOfMarriage,
      minister: minister,
      licenseNumber: licenseNumber,
      observations: observations,
      selected: selected,
    );
  }
}
