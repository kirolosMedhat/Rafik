/// Rafik (رفيق) — Egyptian National ID Validation & Gender Parity Utility
///
/// Encodes official Egyptian National ID card structure (14 digits):
/// - Digit 1: Century (2 for 1900-1999, 3 for 2000-2099)
/// - Digits 2-7: Birth Date (YYMMDD)
/// - Digits 8-9: Governorate Code (01: Cairo, 02: Alexandria, 21: Giza, etc.)
/// - Digits 10-13: Birth Sequence Number
///   - Digit 13 (second to last): Gender Parity
///     * Odd (1, 3, 5, 7, 9) = Male
///     * Even (0, 2, 4, 6, 8) = Female
/// - Digit 14: Checksum Digit
class NationalIdUtils {
  NationalIdUtils._();

  /// Valid Egyptian governorate codes (Civil Registration)
  static const Set<String> validGovernorateCodes = {
    '01', // Cairo
    '02', // Alexandria
    '03', // Port Said
    '04', // Suez
    '11', // Damietta
    '12', // Dakahlia
    '13', // Ash Sharqia
    '14', // Kaliobeya
    '15', // Kafr El Sheikh
    '16', // Gharbia
    '17', // Monufia
    '18', // El Beheira
    '19', // Ismailia
    '21', // Giza
    '22', // Beni Suef
    '23', // Faiyum
    '24', // Minya
    '25', // Asyut
    '26', // Sohag
    '27', // Qena
    '28', // Aswan
    '29', // Luxor
    '31', // Red Sea
    '32', // New Valley
    '33', // Matrouh
    '34', // North Sinai
    '35', // South Sinai
    '88', // Born Abroad
  };

  /// Validates a 14-digit Egyptian National ID.
  /// Throws [FormatException] if invalid.
  static void validate(String rawId) {
    final trimmed = rawId.trim();
    if (trimmed.length != 14 || !RegExp(r'^\d{14}$').hasMatch(trimmed)) {
      throw const FormatException(
        'National ID must be exactly 14 digits.\n'
        'الرقم القومي يجب أن يتكون من 14 رقماً بالتمام.',
      );
    }

    final century = int.parse(trimmed[0]);
    if (century != 2 && century != 3) {
      throw const FormatException(
        'Invalid century indicator in National ID.\n'
        'الرقم الأول في البطاقة القومية غير صحيح (يجب أن يكون 2 أو 3).',
      );
    }

    final yearPart = int.parse(trimmed.substring(1, 3));
    final month = int.parse(trimmed.substring(3, 5));
    final day = int.parse(trimmed.substring(5, 7));

    if (month < 1 || month > 12) {
      throw const FormatException('Invalid birth month in National ID / شهر الميلاد في الرقم القومي غير صحيح');
    }
    if (day < 1 || day > 31) {
      throw const FormatException('Invalid birth day in National ID / يوم الميلاد في الرقم القومي غير صحيح');
    }

    final fullYear = (century == 2 ? 1900 : 2000) + yearPart;
    final now = DateTime.now();
    try {
      final birthDate = DateTime(fullYear, month, day);
      if (birthDate.isAfter(now)) {
        throw const FormatException('Birth date cannot be in the future / تاريخ الميلاد لا يمكن أن يكون في المستقبل');
      }
      final age = now.year - fullYear;
      if (age < 18) {
        throw const FormatException(
          'Driver must be at least 18 years old.\n'
          'يجب أن يكون عمر الكابتن 18 عاماً على الأقل.',
        );
      }
    } catch (e) {
      if (e is FormatException) rethrow;
      throw const FormatException('Invalid calendar date in National ID / تاريخ ميلاد غير متوافق تقويمياً');
    }

    final govCode = trimmed.substring(7, 9);
    if (!validGovernorateCodes.contains(govCode)) {
      throw FormatException('Invalid governorate code ($govCode) in National ID / كود المحافظة غير صحيح');
    }
  }

  /// Determines gender from the 13th digit of the 14-digit Egyptian National ID.
  /// Odd = Male ('male'), Even = Female ('female').
  static String getGender(String rawId) {
    validate(rawId);
    final thirteenthDigit = int.parse(rawId.trim()[12]);
    return (thirteenthDigit % 2 == 1) ? 'male' : 'female';
  }

  /// Verifies if the national ID matches the specified gender.
  static bool matchesGender(String rawId, String gender) {
    try {
      final derived = getGender(rawId);
      return derived.toLowerCase() == gender.toLowerCase();
    } catch (_) {
      return false;
    }
  }

  /// Returns true if the national ID is confirmed female for the Rafik Girl service.
  static bool isFemale(String rawId) {
    return matchesGender(rawId, 'female');
  }
}
