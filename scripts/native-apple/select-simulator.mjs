import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

function selectIPhoneSimulator(payload) {
  const candidates = Object.values(payload.devices ?? {}).flat();
  const device = candidates.find(
    (candidate) => candidate.isAvailable && candidate.name?.startsWith('iPhone'),
  );

  if (!device) throw new Error('No available iPhone simulator found.');
  return device;
}

export function selectSimulatorName(payload) {
  return selectIPhoneSimulator(payload).name;
}

export function selectSimulatorUDID(payload) {
  const device = selectIPhoneSimulator(payload);
  if (!device.udid) throw new Error('Available iPhone simulator has no UDID.');
  return device.udid;
}

export function hasEligibleSimulatorDestination(output) {
  const eligible = output.split('Ineligible destinations')[0];
  return eligible.includes('platform:iOS Simulator');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const input = readFileSync(0, 'utf8');
  if (process.argv[2] === '--eligible') {
    process.stdout.write(hasEligibleSimulatorDestination(input) ? 'yes\n' : 'no\n');
  } else if (process.argv[2] === '--udid') {
    process.stdout.write(`${selectSimulatorUDID(JSON.parse(input))}\n`);
  } else {
    process.stdout.write(`${selectSimulatorName(JSON.parse(input))}\n`);
  }
}
