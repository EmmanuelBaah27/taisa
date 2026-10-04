import assert from 'node:assert/strict';
import test from 'node:test';

import { selectSimulatorUDID } from '../select-simulator.mjs';

test('selects an available simulator by device family instead of a model name', () => {
  const devices = {
    devices: {
      'com.apple.CoreSimulator.SimRuntime.iOS-26-5': [
        { name: 'iPhone 17 Pro', udid: 'PHONE-UDID', isAvailable: true },
        { name: 'iPad Air 13-inch (M3)', udid: 'IPAD-UDID', isAvailable: true },
      ],
      'com.apple.CoreSimulator.SimRuntime.iOS-26-1': [
        { name: 'iPad Pro 11-inch (M5)', udid: 'UNAVAILABLE-IPAD', isAvailable: false },
      ],
    },
  };

  assert.equal(selectSimulatorUDID(devices, 'iPhone'), 'PHONE-UDID');
  assert.equal(selectSimulatorUDID(devices, 'iPad'), 'IPAD-UDID');
});

test('fails clearly when the requested simulator family is unavailable', () => {
  assert.throws(
    () => selectSimulatorUDID({ devices: {} }, 'iPad'),
    /No available iPad simulator found/,
  );
});
