import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

describe('VoiceEntryButton liquid glass migration', () => {
  test('preserves the 104 by 56 voice-entry geometry and accent identity', () => {
    const source = readFileSync(resolve(__dirname, '../VoiceEntryButton.tsx'), 'utf8');

    expect(source).toContain('width: 104');
    expect(source).toContain('height: 56');
    expect(source).toContain('hierarchy="prominent"');
    expect(source).toContain('tone="accent"');
    expect(source).toContain('<LiquidGlassButtonSurface');
  });
});
