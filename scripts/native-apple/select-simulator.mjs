import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

export function selectSimulatorUDID(payload, family) {
  const eligibleDestinations = payload.split('Ineligible destinations')[0];
  const escapedFamily = family.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = eligibleDestinations.match(
    new RegExp(`\\{[^}]*\\bid:([^,}]+)[^}]*\\bname:(${escapedFamily}[^,}]*)[^}]*\\}`),
  );

  if (!match) throw new Error(`No available ${family} simulator found.`);
  return match[1].trim();
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const family = process.argv[2];
  const payload = readFileSync(0, 'utf8');
  process.stdout.write(`${selectSimulatorUDID(payload, family)}\n`);
}
