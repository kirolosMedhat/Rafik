/**
 * Rafik Enterprise Cloud Functions (v2) Entrypoint
 * Fully server-authoritative ride dispatch, dynamic pricing, and security governance.
 */
import * as admin from 'firebase-admin';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
// Initialize Firebase Admin SDK singleton
if (!admin.apps.length) {
    admin.initializeApp();
}
import { executeAdminResolveSos, executeAdminReviewDriver, executeAdminReviewIdentity, executeAdminSuspendDriver, executeAdminUpdateSettings, executeGetAdminMetrics, } from './admin.js';
import { executeRegisterUserProfile } from './auth.js';
import { executeAcceptRide, executeCancelRide, executeCompleteRide, executeMarkArrived, executeRateRide, executeRequestRide, executeVerifyPinAndStartTrip, } from './rides.js';
import { executeRadiusExpansionAndExpirationSweep } from './triggers.js';
// ============================================================================
// 1. AUTHENTICATION & ONBOARDING
// ============================================================================
export const registerUserProfile = onCall({ region: 'europe-west1' }, async (request) => {
    if (!request.auth) {
        throw new HttpsError('unauthenticated', 'Caller must be authenticated via phone OTP.');
    }
    try {
        const payload = request.data;
        return await executeRegisterUserProfile(request.auth.uid, request.auth.token.phone_number, payload);
    }
    catch (error) {
        throw new HttpsError('invalid-argument', error.message);
    }
});
// ============================================================================
// 2. RIDE LIFECYCLE & DISPATCH OPERATIONS
// ============================================================================
export const requestRide = onCall({ region: 'europe-west1' }, async (request) => {
    if (!request.auth) {
        throw new HttpsError('unauthenticated', 'User must be authenticated.');
    }
    try {
        const payload = request.data;
        return await executeRequestRide(request.auth.uid, payload);
    }
    catch (error) {
        throw new HttpsError('failed-precondition', error.message);
    }
});
export const acceptRide = onCall({ region: 'europe-west1' }, async (request) => {
    if (!request.auth) {
        throw new HttpsError('unauthenticated', 'Driver must be authenticated.');
    }
    try {
        const offerId = request.data.offerId;
        if (!offerId)
            throw new Error('OFFER_ID_REQUIRED');
        return await executeAcceptRide(request.auth.uid, offerId);
    }
    catch (error) {
        throw new HttpsError('aborted', error.message);
    }
});
export const markArrived = onCall({ region: 'europe-west1' }, async (request) => {
    if (!request.auth) {
        throw new HttpsError('unauthenticated', 'Driver must be authenticated.');
    }
    try {
        const { rideId, currentLat, currentLng } = request.data;
        if (!rideId)
            throw new Error('RIDE_ID_REQUIRED');
        return await executeMarkArrived(request.auth.uid, rideId, currentLat, currentLng);
    }
    catch (error) {
        throw new HttpsError('failed-precondition', error.message);
    }
});
export const verifyPinAndStartTrip = onCall({ region: 'europe-west1' }, async (request) => {
    if (!request.auth) {
        throw new HttpsError('unauthenticated', 'Driver must be authenticated.');
    }
    try {
        const { rideId, pin } = request.data;
        if (!rideId || !pin)
            throw new Error('RIDE_ID_AND_PIN_REQUIRED');
        return await executeVerifyPinAndStartTrip(request.auth.uid, rideId, pin);
    }
    catch (error) {
        throw new HttpsError('failed-precondition', error.message);
    }
});
export const completeRide = onCall({ region: 'europe-west1' }, async (request) => {
    if (!request.auth) {
        throw new HttpsError('unauthenticated', 'Driver must be authenticated.');
    }
    try {
        const { rideId } = request.data;
        if (!rideId)
            throw new Error('RIDE_ID_REQUIRED');
        return await executeCompleteRide(request.auth.uid, rideId);
    }
    catch (error) {
        throw new HttpsError('failed-precondition', error.message);
    }
});
export const cancelRide = onCall({ region: 'europe-west1' }, async (request) => {
    if (!request.auth) {
        throw new HttpsError('unauthenticated', 'User must be authenticated.');
    }
    try {
        const { rideId, reason } = request.data;
        if (!rideId)
            throw new Error('RIDE_ID_REQUIRED');
        return await executeCancelRide(request.auth.uid, rideId, reason || 'Cancelled by user');
    }
    catch (error) {
        throw new HttpsError('failed-precondition', error.message);
    }
});
export const rateRide = onCall({ region: 'europe-west1' }, async (request) => {
    if (!request.auth) {
        throw new HttpsError('unauthenticated', 'User must be authenticated.');
    }
    try {
        const { rideId, rating, review } = request.data;
        return await executeRateRide(request.auth.uid, rideId, Number(rating), review);
    }
    catch (error) {
        throw new HttpsError('invalid-argument', error.message);
    }
});
// ============================================================================
// 3. ADMIN OPERATIONS
// ============================================================================
export const adminReviewDriver = onCall({ region: 'europe-west1' }, async (request) => {
    if (!request.auth) {
        throw new HttpsError('unauthenticated', 'Admin authentication required.');
    }
    try {
        const { driverId, approve, reason, confirmFemale } = request.data;
        return await executeAdminReviewDriver(request.auth.uid, driverId, Boolean(approve), reason, Boolean(confirmFemale));
    }
    catch (error) {
        throw new HttpsError('permission-denied', error.message);
    }
});
export const adminSuspendDriver = onCall({ region: 'europe-west1' }, async (request) => {
    if (!request.auth) {
        throw new HttpsError('unauthenticated', 'Admin authentication required.');
    }
    try {
        const { driverId, reason } = request.data;
        if (!driverId)
            throw new Error('DRIVER_ID_REQUIRED');
        return await executeAdminSuspendDriver(request.auth.uid, driverId, reason);
    }
    catch (error) {
        throw new HttpsError('permission-denied', error.message);
    }
});
export const adminReviewIdentity = onCall({ region: 'europe-west1' }, async (request) => {
    if (!request.auth) {
        throw new HttpsError('unauthenticated', 'Admin authentication required.');
    }
    try {
        const { userId, approve, reason } = request.data;
        return await executeAdminReviewIdentity(request.auth.uid, userId, Boolean(approve), reason);
    }
    catch (error) {
        throw new HttpsError('permission-denied', error.message);
    }
});
export const adminResolveSos = onCall({ region: 'europe-west1' }, async (request) => {
    if (!request.auth) {
        throw new HttpsError('unauthenticated', 'Admin authentication required.');
    }
    try {
        const { sosId, notes } = request.data;
        return await executeAdminResolveSos(request.auth.uid, sosId, notes || 'Resolved by operations');
    }
    catch (error) {
        throw new HttpsError('permission-denied', error.message);
    }
});
export const adminUpdateSettings = onCall({ region: 'europe-west1' }, async (request) => {
    if (!request.auth) {
        throw new HttpsError('unauthenticated', 'Admin authentication required.');
    }
    try {
        return await executeAdminUpdateSettings(request.auth.uid, request.data);
    }
    catch (error) {
        throw new HttpsError('permission-denied', error.message);
    }
});
export const getAdminMetrics = onCall({ region: 'europe-west1' }, async (request) => {
    if (!request.auth) {
        throw new HttpsError('unauthenticated', 'Admin authentication required.');
    }
    try {
        return await executeGetAdminMetrics(request.auth.uid);
    }
    catch (error) {
        throw new HttpsError('permission-denied', error.message);
    }
});
// ============================================================================
// 4. SCHEDULED BACKGROUND DISPATCH CLEANER (Radius Expansion & Expiry)
// ============================================================================
export const expireStaleRidesAndOffers = onSchedule({
    schedule: 'every 1 minutes',
    region: 'europe-west1',
}, async () => {
    const result = await executeRadiusExpansionAndExpirationSweep();
    console.log('[Dispatcher Sweep]', result);
});
//# sourceMappingURL=index.js.map