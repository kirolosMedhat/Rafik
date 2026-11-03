/**
 * Rafik Server-Authoritative Admin Operations Engine
 * Condition 3 compliant: Only verified administrators can execute approvals,
 * settings modifications, and security overrides.
 */
import * as admin from 'firebase-admin';
function getAdmin() {
    return admin.default || admin;
}
import { invalidateSettingsCache } from './config.js';
/**
 * Asserts that the caller possesses system administrator privileges.
 */
export async function assertAdmin(callerUid) {
    const user = await getAdmin().auth().getUser(callerUid);
    const claims = user.customClaims;
    const isAdminClaim = claims?.role === 'admin' || claims?.admin === true;
    if (!isAdminClaim) {
        const adminDoc = await getAdmin().firestore().collection('admin_users').doc(callerUid).get();
        if (!adminDoc.exists || !adminDoc.data()?.is_active) {
            throw new Error('FORBIDDEN: Requires administrative privileges.');
        }
    }
}
/**
 * Admin Review & Vetting of Captain Applications
 */
export async function executeAdminReviewDriver(callerUid, driverId, approve, reason, confirmFemale = false) {
    await assertAdmin(callerUid);
    const db = getAdmin().firestore();
    const driverRef = db.collection('drivers').doc(driverId);
    const driverSnap = await driverRef.get();
    if (!driverSnap.exists)
        throw new Error('DRIVER_NOT_FOUND');
    if (approve) {
        // 1. Update Driver Profile
        await driverRef.update({
            status: 'approved',
            rejection_reason: null,
            approved_by: callerUid,
            approved_at: getAdmin().firestore.FieldValue.serverTimestamp(),
            updated_at: getAdmin().firestore.FieldValue.serverTimestamp(),
        });
        // 2. Mark All 6 KYC Document Sides Approved
        const docsSnapshot = await db.collection('driver_documents').doc(driverId).collection('items').get();
        const batch = db.batch();
        for (const doc of docsSnapshot.docs) {
            batch.update(doc.ref, {
                status: 'approved',
                reviewed_by: callerUid,
                reviewed_at: getAdmin().firestore.FieldValue.serverTimestamp(),
            });
        }
        await batch.commit();
        // 3. If confirming female for Rafik Girl:
        if (confirmFemale) {
            await db.collection('users').doc(driverId).update({
                gender_verified: true,
                updated_at: getAdmin().firestore.FieldValue.serverTimestamp(),
            });
        }
        // 4. Update Firebase Auth Custom Claims (Approved Captain Token)
        await getAdmin().auth().setCustomUserClaims(driverId, {
            role: 'driver',
            driver: true,
            approved: true,
            gender_verified: confirmFemale,
        });
        // 5. Update RTDB Location Status & Clear Any Suspension
        try {
            await Promise.all([
                getAdmin().database().ref(`driver_locations/${driverId}`).update({
                    status: 'approved',
                    gender_verified: confirmFemale,
                }),
                getAdmin().database().ref(`suspended_drivers/${driverId}`).remove(),
            ]);
        }
        catch (_) { }
    }
    else {
        // Rejection
        if (!reason || reason.trim() === '') {
            throw new Error('REJECTION_REASON_REQUIRED: A valid rejection reason must be supplied.');
        }
        await driverRef.update({
            status: 'rejected',
            rejection_reason: reason.trim(),
            approved_by: null,
            approved_at: null,
            updated_at: getAdmin().firestore.FieldValue.serverTimestamp(),
        });
        await getAdmin().auth().setCustomUserClaims(driverId, {
            role: 'driver',
            driver: true,
            approved: false,
        });
        try {
            await Promise.all([
                getAdmin().database().ref(`driver_locations/${driverId}`).update({
                    status: 'rejected',
                    is_online: false,
                }),
                getAdmin().database().ref(`driver_presence/${driverId}`).set({
                    state: 'offline',
                    last_changed: Date.now(),
                }),
            ]);
        }
        catch (_) { }
    }
    return { success: true };
}
/**
 * Admin Suspension / Deactivation of a Driver Captain
 * Revokes refresh tokens and sets server-authoritative RTDB suspension node
 * to instantly block active WebSockets and stale unexpired ID tokens.
 */
export async function executeAdminSuspendDriver(callerUid, driverId, reason) {
    await assertAdmin(callerUid);
    const db = getAdmin().firestore();
    const driverRef = db.collection('drivers').doc(driverId);
    const driverSnap = await driverRef.get();
    if (!driverSnap.exists)
        throw new Error('DRIVER_NOT_FOUND');
    // 1. Update Firestore Profile
    await driverRef.update({
        status: 'suspended',
        rejection_reason: reason ?? 'Account suspended by platform administration',
        is_online: false,
        updated_at: getAdmin().firestore.FieldValue.serverTimestamp(),
    });
    // 2. Revoke Firebase Auth Refresh Tokens immediately
    try {
        await getAdmin().auth().revokeRefreshTokens(driverId);
    }
    catch (_) { }
    // 3. Update Custom Claims
    await getAdmin().auth().setCustomUserClaims(driverId, {
        role: 'driver',
        driver: true,
        approved: false,
        suspended: true,
    });
    // 4. Server-Authoritative RTDB Revocation Node (Instant revocation for active WebSockets & unexpired tokens)
    try {
        const rtdb = getAdmin().database();
        await Promise.all([
            rtdb.ref(`suspended_drivers/${driverId}`).set({
                suspended_at: Date.now(),
                reason: reason ?? 'Account suspended by platform administration',
            }),
            rtdb.ref(`driver_locations/${driverId}`).update({
                status: 'suspended',
                is_online: false,
            }),
            rtdb.ref(`driver_presence/${driverId}`).set({
                state: 'offline',
                last_changed: Date.now(),
            }),
        ]);
    }
    catch (_) { }
    return { success: true };
}
/**
 * Admin Review of Passenger Identity Proofs for Rafik Girl
 */
export async function executeAdminReviewIdentity(callerUid, userId, approve, reason) {
    await assertAdmin(callerUid);
    const db = getAdmin().firestore();
    const userRef = db.collection('users').doc(userId);
    const userSnap = await userRef.get();
    if (!userSnap.exists)
        throw new Error('USER_NOT_FOUND');
    if (approve) {
        await userRef.update({
            gender_verified: true,
            updated_at: getAdmin().firestore.FieldValue.serverTimestamp(),
        });
        const user = await getAdmin().auth().getUser(userId);
        await getAdmin().auth().setCustomUserClaims(userId, {
            ...user.customClaims,
            gender_verified: true,
        });
    }
    else {
        await userRef.update({
            gender_verified: false,
            verification_notes: reason ?? 'Identity documents rejected by administration',
            updated_at: getAdmin().firestore.FieldValue.serverTimestamp(),
        });
    }
    return { success: true };
}
/**
 * Admin SOS Distress Incident Resolution
 */
export async function executeAdminResolveSos(callerUid, sosId, notes) {
    await assertAdmin(callerUid);
    const db = getAdmin().firestore();
    const sosRef = db.collection('sos_events').doc(sosId);
    const sosSnap = await sosRef.get();
    if (!sosSnap.exists)
        throw new Error('SOS_NOT_FOUND');
    await sosRef.update({
        status: 'resolved',
        resolved_by: callerUid,
        resolved_at: getAdmin().firestore.FieldValue.serverTimestamp(),
        notes: notes.trim(),
    });
    return { success: true };
}
/**
 * Admin Dynamic Platform Configuration Update
 * Condition 4 compliant: Commercial rules updated at runtime without redeployment.
 */
export async function executeAdminUpdateSettings(callerUid, newSettings) {
    await assertAdmin(callerUid);
    const db = getAdmin().firestore();
    await db.collection('app_settings').doc('global').set(newSettings, { merge: true });
    invalidateSettingsCache();
    return { success: true };
}
/**
 * Admin Dashboard Live Platform Metrics
 */
export async function executeGetAdminMetrics(callerUid) {
    await assertAdmin(callerUid);
    const db = getAdmin().firestore();
    const [activeDriversSnap, completedRidesSnap, activeSosSnap] = await Promise.all([
        db.collection('drivers').where('is_online', '==', true).where('status', '==', 'approved').count().get(),
        db.collection('rides').where('status', '==', 'completed').count().get(),
        db.collection('sos_events').where('status', '==', 'active').count().get(),
    ]);
    return {
        active_online_drivers: activeDriversSnap.data().count,
        completed_rides: completedRidesSnap.data().count,
        active_sos_alerts: activeSosSnap.data().count,
        timestamp: Date.now(),
    };
}
//# sourceMappingURL=admin.js.map