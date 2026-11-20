import assert from 'node:assert/strict';
import test from 'node:test';

import {
  hasEligibleSimulatorDestination,
  selectSimulatorName,
  selectSimulatorUDID,
} from '../select-simulator.mjs';

test('selects an available iPhone simulator instead of a model name', () => {
  const devices = {
    devices: {
      runtime: [
        { name: 'iPhone 17 Pro', udid: 'PHONE-UDID', isAvailable: true },
        { name: 'iPad Air 13-inch (M3)', udid: 'IPAD-UDID', isAvailable: true },
        { name: 'iPad Pro 11-inch (M5)', udid: 'UNAVAILABLE-IPAD', isAvailable: false },
      ],
    },
  };

  assert.equal(selectSimulatorName(devices), 'iPhone 17 Pro');
  assert.equal(selectSimulatorUDID(devices), 'PHONE-UDID');
});

test('fails clearly when the selected simulator has no UDID', () => {
  assert.throws(
    () => selectSimulatorUDID({
      devices: { runtime: [{ name: 'iPhone 17 Pro', isAvailable: true }] },
    }),
    /Available iPhone simulator has no UDID/,
  );
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

test('fails clearly when an iPhone simulator is unavailable', () => {
  assert.throws(
    () => selectSimulatorName({ devices: {} }),
    /No available iPhone simulator found/,
  );
});
