import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

export function selectSimulatorName(payload) {
  const candidates = Object.values(payload.devices ?? {}).flat();
  const device = candidates.find(
    (candidate) => candidate.isAvailable && candidate.name?.startsWith('iPhone'),
  );

  if (!device) throw new Error('No available iPhone simulator found.');
  return device.name;
}

export function hasEligibleSimulatorDestination(output) {
  const eligible = output.split('Ineligible destinations')[0];
  return eligible.includes('platform:iOS Simulator');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const input = readFileSync(0, 'utf8');
  if (process.argv[2] === '--eligible') {
    process.stdout.write(hasEligibleSimulatorDestination(input) ? 'yes\n' : 'no\n');
  } else {
    process.stdout.write(`${selectSimulatorName(JSON.parse(input))}\n`);
  }
}
