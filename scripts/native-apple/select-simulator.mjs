import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

export function selectSimulatorName(payload, family) {
  const candidates = Object.values(payload.devices ?? {}).flat();
  const device = candidates.find(
    (candidate) => candidate.isAvailable && candidate.name?.startsWith(family),
  );

  if (!device) throw new Error(`No available ${family} simulator found.`);
  return device.name;
}

export function hasEligibleSimulatorDestination(output) {
  const eligible = output.split('Ineligible destinations')[0];
  return eligible.includes('platform:iOS Simulator');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const family = process.argv[2];
  const input = readFileSync(0, 'utf8');
  if (family === '--eligible') {
    process.stdout.write(hasEligibleSimulatorDestination(input) ? 'yes\n' : 'no\n');
  } else {
    process.stdout.write(`${selectSimulatorName(JSON.parse(input), family)}\n`);
  }
}
