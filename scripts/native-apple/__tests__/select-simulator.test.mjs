import assert from 'node:assert/strict';
import test from 'node:test';

import { selectSimulatorUDID } from '../select-simulator.mjs';

test('selects an available simulator by device family instead of a model name', () => {
  const destinations = `
Available destinations for the "Taisa-Preview" scheme:
  { platform:iOS Simulator, arch:arm64, id:PHONE-UDID, OS:26.5, name:iPhone 17 Pro }
  { platform:iOS Simulator, arch:arm64, id:IPAD-UDID, OS:26.5, name:iPad Air 13-inch (M3) }
Ineligible destinations for the "Taisa-Preview" scheme:
  { platform:iOS Simulator, id:UNAVAILABLE-IPAD, OS:26.1, name:iPad Pro 11-inch (M5) }
`;

  assert.equal(selectSimulatorUDID(destinations, 'iPhone'), 'PHONE-UDID');
  assert.equal(selectSimulatorUDID(destinations, 'iPad'), 'IPAD-UDID');
});

test('fails clearly when the requested simulator family is unavailable', () => {
  assert.throws(
    () => selectSimulatorUDID('Available destinations:\n', 'iPad'),
    /No available iPad simulator found/,
  );
});
