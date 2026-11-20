import assert from 'node:assert/strict';
import test from 'node:test';

import {
  hasEligibleSimulatorDestination,
  selectEligibleSimulatorUDID,
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
  const output = `
Available destinations:
  { platform:iOS Simulator, id:PHONE, name:iPhone 17 Pro }
Ineligible destinations:
  { platform:iOS, name:Any iOS Device }
`;
  assert.equal(hasEligibleSimulatorDestination(output), true);
  assert.equal(selectEligibleSimulatorUDID(output), 'PHONE');
  assert.equal(hasEligibleSimulatorDestination(`
Available destinations:
Ineligible destinations:
  { platform:iOS, name:Any iOS Device }
`), false);
});

test('rejects an ineligible or placeholder simulator destination', () => {
  assert.throws(
    () => selectEligibleSimulatorUDID(`
Available destinations:
  { platform:iOS Simulator, id:dvtdevice-DVTiOSDeviceSimulatorPlaceholder, name:Any iOS Simulator Device }
Ineligible destinations:
  { platform:iOS Simulator, id:OLD-PHONE, name:iPhone 17 Pro }
`),
    /No eligible iPhone simulator destination found/,
  );
});

test('fails clearly when an iPhone simulator is unavailable', () => {
  assert.throws(
    () => selectSimulatorName({ devices: {} }),
    /No available iPhone simulator found/,
  );
});
