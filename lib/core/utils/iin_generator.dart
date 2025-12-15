import 'dart:math';

/// IIN (Identity Identification Number) Generator
///
/// Format: XXXX-YYMM-RRRR-RRRR
/// - XXXX: Century (20) + Type Code (AA=Personal, EE=Entity)
/// - YYMM: Year (25) + Month (12)
/// - RRRR-RRRR: Random hex (8 characters)
///
/// Examples:
/// - 20AA-2512-A7F3-B82E (Personal user, Dec 2025)
/// - 20EE-2512-C4D1-9E2F (Entity, Dec 2025)

class IINGenerator {
  static const String _century = '20';
  static const String _personalCode = 'AA';
  static const String _entityCode = 'EE';
  static const String _entityEmployeeCode = 'AE'; // Employee under entity

  static final Random _random = Random.secure();

  /// Generate a Personal IIN (20AA-YYMM-XXXX-XXXX)
  static String generatePersonalIIN() {
    return _generateIIN(_personalCode);
  }

  /// Generate an Entity IIN (20EE-YYMM-XXXX-XXXX)
  static String generateEntityIIN() {
    return _generateIIN(_entityCode);
  }

  /// Generate an Entity Employee IIN (20AE-YYMM-XXXX-XXXX)
  static String generateEntityEmployeeIIN() {
    return _generateIIN(_entityEmployeeCode);
  }

  static String _generateIIN(String typeCode) {
    final now = DateTime.now();
    final year = (now.year % 100).toString().padLeft(2, '0');
    final month = now.month.toString().padLeft(2, '0');
    final randomCluster = _generateHex(4);
    final randomSuffix = _generateHex(4);

    return '$_century$typeCode-$year$month-$randomCluster-$randomSuffix';
  }

  static String _generateHex(int length) {
    const hexChars = '0123456789ABCDEF';
    return List.generate(length, (_) => hexChars[_random.nextInt(16)]).join();
  }

  /// Parse IIN to extract metadata
  static IINMetadata? parseIIN(String iin) {
    final parts = iin.split('-');
    if (parts.length != 4) return null;

    final prefix = parts[0];
    final datePart = parts[1];

    if (prefix.length != 4 || datePart.length != 4) return null;

    final typeCode = prefix.substring(2, 4);
    final year = int.tryParse(datePart.substring(0, 2));
    final month = int.tryParse(datePart.substring(2, 4));

    if (year == null || month == null) return null;

    IINType type;
    switch (typeCode) {
      case _personalCode:
        type = IINType.personal;
        break;
      case _entityCode:
        type = IINType.entity;
        break;
      case _entityEmployeeCode:
        type = IINType.entityEmployee;
        break;
      default:
        return null;
    }

    return IINMetadata(
      iin: iin,
      type: type,
      createdYear: 2000 + year,
      createdMonth: month,
    );
  }

  /// Validate IIN format
  static bool isValidIIN(String iin) {
    return parseIIN(iin) != null;
  }
}

enum IINType {
  personal,
  entity,
  entityEmployee,
}

class IINMetadata {
  final String iin;
  final IINType type;
  final int createdYear;
  final int createdMonth;

  IINMetadata({
    required this.iin,
    required this.type,
    required this.createdYear,
    required this.createdMonth,
  });

  String get typeLabel {
    switch (type) {
      case IINType.personal:
        return 'Personal';
      case IINType.entity:
        return 'Entity';
      case IINType.entityEmployee:
        return 'Entity Employee';
    }
  }

  String get createdDate => '$createdYear-${createdMonth.toString().padLeft(2, '0')}';
}
