/**
 * Rafik Authoritative Pricing Engine
 * Server-authoritative computation using dynamic settings.
 * Condition 3 & Condition 4 compliant: Clients cannot tamper with pricing.
 */
import { getPlatformSettings } from './config.js';
export async function computeAuthoritativeFare(distanceKm, tier, isNight = false, overrideSettings) {
    const settings = overrideSettings ?? await getPlatformSettings();
    const pricing = settings.pricing;
    // 1. Calculate raw distance fare
    const baseFare = pricing.base_fare_egp;
    const distanceFare = distanceKm * pricing.per_km_rate_egp;
    let multiplier = 1.0;
    if (tier === 'rafik_girl') {
        multiplier *= pricing.rafik_girl_premium_multiplier;
    }
    if (isNight) {
        multiplier *= pricing.night_multiplier;
    }
    const rawFare = (baseFare + distanceFare) * multiplier;
    const fare = Math.max(pricing.min_fare_egp, Math.round(rawFare * 100) / 100);
    // 2. Calculate driver earnings & platform commission
    const driverEarnings = Math.round(fare * (1.0 - pricing.platform_commission_rate) * 100) / 100;
    const platformFee = Math.round((fare - driverEarnings) * 100) / 100;
    return {
        distance_km: Math.round(distanceKm * 100) / 100,
        fare_egp: fare,
        driver_earnings_egp: driverEarnings,
        platform_fee_egp: platformFee,
        breakdown: {
            base_fare: baseFare,
            distance_fare: Math.round(distanceFare * 100) / 100,
            tier_multiplier: multiplier,
            commission_rate: pricing.platform_commission_rate,
        },
    };
}
//# sourceMappingURL=pricing.js.map