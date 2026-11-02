/**
 * Rafik Spatial & Demographics Verification Utilities
 */

/**
 * Calculates Haversine great-circle distance between two GPS coordinates in kilometers.
 */
export function haversineDistanceKm(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number
): number {
  const R = 6371; // Earth's mean radius in km
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLon = ((lon2 - lon1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

/**
 * Calculates approximate Cairo urban road routing distance.
 * Straight-line distance multiplied by the Cairo traffic detour factor (default: 1.25).
 */
export function approximateRoadDistanceKm(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number,
  trafficMultiplier = 1.25
): number {
  const directKm = haversineDistanceKm(lat1, lon1, lat2, lon2);
  return Math.round(directKm * trafficMultiplier * 100) / 100;
}

/**
 * Egyptian National ID 13th-Digit Parity Verification.
 * Egyptian National ID consists of 14 digits: C YY MM DD SS GGG G C
 * Digit 13 (0-indexed position 12) encodes legal gender:
 * - Odd digit (1, 3, 5, 7, 9) = Male (ذكر)
 * - Even digit (0, 2, 4, 6, 8) = Female (أنثى)
 */
export function nationalIdGender(nationalId: string): 'female' | 'male' | null {
  const clean = nationalId.trim();
  if (!/^[23]\d{13}$/.test(clean)) {
    return null;
  }
  const genderDigit = parseInt(clean.charAt(12), 10);
  return genderDigit % 2 === 0 ? 'female' : 'male';
}

/**
 * Validates and normalizes Egyptian mobile numbers to canonical E.164 (+201XXXXXXXXX).
 */
export function normalizeEgyptianPhone(phone: string): string | null {
  const clean = phone.replace(/[\s\-\(\)]/g, '');
  let digits = clean;

  if (digits.startsWith('0020')) {
    digits = digits.substring(4);
  } else if (digits.startsWith('+20')) {
    digits = digits.substring(3);
  } else if (digits.startsWith('20') && digits.length === 12) {
    digits = digits.substring(2);
  } else if (digits.startsWith('0')) {
    digits = digits.substring(1);
  }

  // Egyptian numbers have 10 digits after removing country code / leading zero
  // and must start with 10, 11, 12, or 15
  if (/^1[0125]\d{8}$/.test(digits)) {
    return `+20${digits}`;
  }

  return null;
}
