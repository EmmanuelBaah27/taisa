import fs from 'node:fs';
import path from 'node:path';

describe('Chats list spacing', () => {
  const source = fs.readFileSync(
    path.resolve(__dirname, '../../../app/(tabs)/chats.tsx'),
    'utf8',
  );

  test('keeps each date beneath the title until its section is complete', () => {
    expect(source).toContain('<SectionList');
    expect(source).toContain('stickySectionHeadersEnabled');
    expect(source).toContain('renderSectionHeader');
  });
});
