import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

describe('Rafik Ride State Machine & Security Invariants', () => {

  describe('1. PIN Handshake Lockout Logic (3 Attempts Maximum)', () => {
    it('accurately simulates progressive PIN failure and irrevocable lockout at attempt 3', () => {
      const storedPin = '8392';
      let currentAttempts = 0;
      let isLocked = false;
      const maxAttempts = 3;

      function verifyPin(inputPin) {
        if (isLocked || currentAttempts >= maxAttempts) {
          return { success: false, status: 'locked', attempts_left: 0, is_locked: true };
        }
        if (inputPin === storedPin) {
          return { success: true, status: 'in_progress', attempts_left: maxAttempts - currentAttempts, is_locked: false };
        }
        currentAttempts += 1;
        isLocked = currentAttempts >= maxAttempts;
        return {
          success: false,
          status: isLocked ? 'locked' : 'wrong_pin',
          attempts_left: Math.max(0, maxAttempts - currentAttempts),
          is_locked: isLocked,
        };
      }

      // Attempt 1: Wrong PIN
      const res1 = verifyPin('0000');
      assert.equal(res1.success, false);
      assert.equal(res1.status, 'wrong_pin');
      assert.equal(res1.attempts_left, 2);
      assert.equal(res1.is_locked, false);

      // Attempt 2: Wrong PIN
      const res2 = verifyPin('1111');
      assert.equal(res2.success, false);
      assert.equal(res2.status, 'wrong_pin');
      assert.equal(res2.attempts_left, 1);
      assert.equal(res2.is_locked, false);

      // Attempt 3: Wrong PIN -> Irrevocably locked
      const res3 = verifyPin('2222');
      assert.equal(res3.success, false);
      assert.equal(res3.status, 'locked');
      assert.equal(res3.attempts_left, 0);
      assert.equal(res3.is_locked, true);

      // Attempt 4: Even correct PIN fails once locked!
      const res4 = verifyPin('8392');
      assert.equal(res4.success, false);
      assert.equal(res4.status, 'locked');
      assert.equal(res4.is_locked, true);
    });

    it('successfully transitions to in_progress on valid PIN entry within attempt quota', () => {
      const storedPin = '4521';
      let currentAttempts = 1; // 1 previous failure
      let isLocked = false;
      const maxAttempts = 3;

      function verifyPin(inputPin) {
        if (isLocked || currentAttempts >= maxAttempts) {
          return { success: false, status: 'locked', attempts_left: 0, is_locked: true };
        }
        if (inputPin === storedPin) {
          return { success: true, status: 'in_progress', attempts_left: maxAttempts - currentAttempts, is_locked: false };
        }
        currentAttempts += 1;
        isLocked = currentAttempts >= maxAttempts;
        return { success: false, status: 'wrong_pin', attempts_left: maxAttempts - currentAttempts, is_locked };
      }

      const res = verifyPin('4521');
      assert.equal(res.success, true);
      assert.equal(res.status, 'in_progress');
      assert.equal(res.is_locked, false);
    });
  });

  describe('2. Ride Lifecycle State Transitions', () => {
    const validTransitions = {
      'requested': ['accepted', 'cancelled', 'expired'],
      'accepted': ['arrived', 'cancelled'],
      'arrived': ['in_progress', 'cancelled'],
      'in_progress': ['completed'],
      'completed': [],
      'cancelled': [],
      'expired': [],
    };

    function canTransition(current, target) {
      return (validTransitions[current] || []).includes(target);
    }

    it('enforces legal forward trip transitions', () => {
      assert.ok(canTransition('requested', 'accepted'));
      assert.ok(canTransition('accepted', 'arrived'));
      assert.ok(canTransition('arrived', 'in_progress'));
      assert.ok(canTransition('in_progress', 'completed'));
    });

    it('rejects illegal out-of-order state leaps', () => {
      assert.equal(canTransition('requested', 'in_progress'), false, 'Cannot start ride directly from requested');
      assert.equal(canTransition('requested', 'completed'), false, 'Cannot complete unstarted ride');
      assert.equal(canTransition('accepted', 'completed'), false, 'Cannot complete before starting');
      assert.equal(canTransition('completed', 'cancelled'), false, 'Cannot cancel finished ride');
      assert.equal(canTransition('in_progress', 'cancelled'), false, 'Cannot cancel in-progress ride directly without admin');
    });

    it('enforces cancellation window restrictions', () => {
      assert.ok(canTransition('requested', 'cancelled'), 'Rider can cancel requested ride');
      assert.ok(canTransition('accepted', 'cancelled'), 'Can cancel before arrival');
      assert.ok(canTransition('arrived', 'cancelled'), 'Can cancel before pin entry');
    });
  });

  describe('3. Driver Approval Gate Invariants', () => {
    function canDriverReceiveOffers(driver) {
      return driver.status === 'approved' && driver.is_online === true && driver.is_busy === false;
    }

    it('allows only approved, online, unbusy drivers to receive dispatch offers', () => {
      const approvedCaptain = { status: 'approved', is_online: true, is_busy: false };
      assert.equal(canDriverReceiveOffers(approvedCaptain), true);

      const pendingCaptain = { status: 'pending', is_online: true, is_busy: false };
      assert.equal(canDriverReceiveOffers(pendingCaptain), false);

      const rejectedCaptain = { status: 'rejected', is_online: true, is_busy: false };
      assert.equal(canDriverReceiveOffers(rejectedCaptain), false);

      const busyCaptain = { status: 'approved', is_online: true, is_busy: true };
      assert.equal(canDriverReceiveOffers(busyCaptain), false);

      const offlineCaptain = { status: 'approved', is_online: false, is_busy: false };
      assert.equal(canDriverReceiveOffers(offlineCaptain), false);
    });
  });

});
