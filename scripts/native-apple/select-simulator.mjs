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

export function selectEligibleSimulatorUDID(output) {
  const eligible = output.split('Ineligible destinations')[0];
  const destination = eligible.split('\n').find((line) => (
    line.includes('platform:iOS Simulator')
      && /\bname:iPhone\b/.test(line)
      && !line.toLowerCase().includes('placeholder')
  ));
  const udid = destination?.match(/\bid:([^,}]+)/)?.[1]?.trim();

  if (!udid || udid.toLowerCase().includes('placeholder')) {
    throw new Error('No eligible iPhone simulator destination found.');
  }
  return udid;
}

export function hasEligibleSimulatorDestination(output) {
  try {
    selectEligibleSimulatorUDID(output);
    return true;
  } catch {
    return false;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const input = readFileSync(0, 'utf8');
  if (process.argv[2] === '--eligible') {
    process.stdout.write(hasEligibleSimulatorDestination(input) ? 'yes\n' : 'no\n');
  } else if (process.argv[2] === '--eligible-udid') {
    process.stdout.write(`${selectEligibleSimulatorUDID(input)}\n`);
  } else if (process.argv[2] === '--udid') {
    process.stdout.write(`${selectSimulatorUDID(JSON.parse(input))}\n`);
  } else {
    process.stdout.write(`${selectSimulatorName(JSON.parse(input))}\n`);
  }
}
