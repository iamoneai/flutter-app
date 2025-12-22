// IAMONEAI - Fresh Start
import 'dart:math';

/// IIN (Identity Identification Number) Generator
///
/// Format: XXXX-YYMM-RRRR-RRRR
/// - XXXX: Century (20) + Type Code (AA=Personal)
/// - YYMM: Year (25) + Month (12)
/// - RRRR-RRRR: Random hex (8 characters)
///
/// Example: 20AA-2512-A7F3-B82E (Personal user, Dec 2025)
class IINGenerator {
  static const String _century = '20';
  static const String _personalCode = 'AA';

  static final Random _random = Random.secure();

  /// Generate a Personal IIN (20AA-YYMM-XXXX-XXXX)
  static String generatePersonalIIN() {
    return _generateIIN(_personalCode);
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
    if (typeCode != _personalCode) return null;

    return IINMetadata(
      iin: iin,
      createdYear: 2000 + year,
      createdMonth: month,
    );
  }

  /// Validate IIN format
  static bool isValidIIN(String iin) {
    return parseIIN(iin) != null;
  }
}

class IINMetadata {
  final String iin;
  final int createdYear;
  final int createdMonth;

  IINMetadata({
    required this.iin,
    required this.createdYear,
    required this.createdMonth,
  });

  String get createdDate =>
      '$createdYear-${createdMonth.toString().padLeft(2, '0')}';
}
