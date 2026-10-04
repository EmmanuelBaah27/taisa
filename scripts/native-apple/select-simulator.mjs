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

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const family = process.argv[2];
  const payload = JSON.parse(readFileSync(0, 'utf8'));
  process.stdout.write(`${selectSimulatorName(payload, family)}\n`);
}
