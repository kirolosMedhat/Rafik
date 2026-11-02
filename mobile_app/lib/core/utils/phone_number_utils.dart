/// Rafik (رفيق) — Egyptian Phone Number Normalization & Validation Utility
///
/// Complies with Egyptian National Telecom Regulatory Authority (NTRA) format:
/// - 4 mobile network operators:
///     010 (Vodafone Egypt)
///     011 (Etisalat Egypt)
///     012 (Orange Egypt)
///     015 (WE / Telecom Egypt)
/// - Total national length: 11 digits (e.g. `01012345678`)
/// - Standard E.164 international format: `+201XXXXXXXXX` (13 characters)
class PhoneNumberUtils {
  PhoneNumberUtils._();

  /// Regex pattern strictly matching Egyptian E.164 mobile numbers:
  /// Starts with `+20`, followed by `10`, `11`, `12`, or `15`, followed by exactly 7 more digits (total 8 digits after prefix 1).
  static final RegExp egyptianE164Regex = RegExp(r'^\+201[0125]\d{8}$');

  /// Normalizes an input phone number to E.164 standard (+201XXXXXXXXX).
  ///
  /// Handles various common user inputs:
  /// - `01012345678` -> `+201012345678`
  /// - `011 2345 6789` -> `+201123456789`
  /// - `+20 12 3456 7890` -> `+201234567890`
  /// - `00201512345678` -> `+201512345678`
  /// - `201012345678` -> `+201012345678`
  /// - `1012345678` -> `+201012345678`
  ///
  /// Throws [FormatException] if the input cannot be resolved to a valid Egyptian mobile number.
  static String normalizeEgyptianPhone(String input) {
    if (input.trim().isEmpty) {
      throw const FormatException('Phone number cannot be empty / رقم الهاتف لا يمكن أن يكون فارغاً');
    }

    // 1. Remove all spaces, dashes, parentheses, dots
    var cleaned = input.replaceAll(RegExp(r'[\s\-\(\)\.]'), '');

    // 2. Handle international prefix forms
    if (cleaned.startsWith('0020')) {
      cleaned = '+20${cleaned.substring(4)}';
    } else if (cleaned.startsWith('20') && cleaned.length == 12) {
      cleaned = '+$cleaned';
    } else if (cleaned.startsWith('01') && cleaned.length == 11) {
      // Local 11-digit format starting with 01
      cleaned = '+20${cleaned.substring(1)}';
    } else if ((cleaned.startsWith('10') ||
            cleaned.startsWith('11') ||
            cleaned.startsWith('12') ||
            cleaned.startsWith('15')) &&
        cleaned.length == 10) {
      // 10-digit format without leading 0
      cleaned = '+20$cleaned';
    } else if (!cleaned.startsWith('+')) {
      // If user typed 11 digits starting with another prefix
      if (cleaned.startsWith('0')) {
        cleaned = '+20${cleaned.substring(1)}';
      }
    }

    // 3. Final E.164 verification
    if (!egyptianE164Regex.hasMatch(cleaned)) {
      throw FormatException(
        'Invalid Egyptian mobile number. Must start with 010, 011, 012, or 015.\n'
        'رقم هاتف مصري غير صحيح. يجب أن يبدأ بـ 010 أو 011 أو 012 أو 015.',
      );
    }

    return cleaned;
  }

  /// Checks whether the raw string can be normalized to a valid Egyptian mobile number.
  static bool isValidEgyptianPhone(String input) {
    try {
      normalizeEgyptianPhone(input);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Formats a normalized E.164 number for friendly UI display.
  /// Example: `+201012345678` -> `+20 10 1234 5678`
  static String formatForDisplay(String phone) {
    try {
      final e164 = normalizeEgyptianPhone(phone);
      // e164: +20 1X XXXX XXXX
      return '${e164.substring(0, 3)} ${e164.substring(3, 5)} ${e164.substring(5, 9)} ${e164.substring(9)}';
    } catch (_) {
      return phone;
    }
  }

  /// Formats a normalized E.164 number into local Egyptian format (01X XXXX XXXX).
  /// Example: `+201012345678` -> `010 1234 5678`
  static String formatToLocalDisplay(String phone) {
    try {
      final e164 = normalizeEgyptianPhone(phone);
      final national = '0${e164.substring(3)}'; // 01012345678
      return '${national.substring(0, 3)} ${national.substring(3, 7)} ${national.substring(7)}';
    } catch (_) {
      return phone;
    }
  }

  /// Returns the telecommunications operator name for an Egyptian number.
  static String getOperatorName(String phone) {
    try {
      final e164 = normalizeEgyptianPhone(phone);
      final prefix = e164.substring(3, 5); // '10', '11', '12', '15'
      switch (prefix) {
        case '10':
          return 'Vodafone Egypt';
        case '11':
          return 'Etisalat by e&';
        case '12':
          return 'Orange Egypt';
        case '15':
          return 'WE (Telecom Egypt)';
        default:
          return 'Egyptian Network';
      }
    } catch (_) {
      return 'Unknown Operator';
    }
  }
}
