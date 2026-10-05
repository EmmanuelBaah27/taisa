import assert from 'node:assert/strict';
import test from 'node:test';

import {
  hasEligibleSimulatorDestination,
  selectSimulatorName,
} from '../select-simulator.mjs';

test('selects an available simulator by device family instead of a model name', () => {
  const devices = {
    devices: {
      runtime: [
        { name: 'iPhone 17 Pro', udid: 'PHONE-UDID', isAvailable: true },
        { name: 'iPad Air 13-inch (M3)', udid: 'IPAD-UDID', isAvailable: true },
        { name: 'iPad Pro 11-inch (M5)', udid: 'UNAVAILABLE-IPAD', isAvailable: false },
      ],
    },
  };

  assert.equal(selectSimulatorName(devices, 'iPhone'), 'iPhone 17 Pro');
  assert.equal(selectSimulatorName(devices, 'iPad'), 'iPad Air 13-inch (M3)');
});

test('detects whether Xcode has an eligible simulator runtime', () => {
  assert.equal(hasEligibleSimulatorDestination(`
Available destinations:
  { platform:iOS Simulator, id:PHONE, name:iPhone 17 Pro }
Ineligible destinations:
  { platform:iOS, name:Any iOS Device }
`), true);
  assert.equal(hasEligibleSimulatorDestination(`
Available destinations:
Ineligible destinations:
  { platform:iOS, name:Any iOS Device }
`), false);
});

test('fails clearly when the requested simulator family is unavailable', () => {
  assert.throws(
    () => selectSimulatorName({ devices: {} }, 'iPad'),
    /No available iPad simulator found/,
  );
});
