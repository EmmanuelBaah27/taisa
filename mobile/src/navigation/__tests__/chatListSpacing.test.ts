import fs from 'node:fs';
import path from 'node:path';

describe('Chats list spacing', () => {
  const source = fs.readFileSync(
    path.resolve(__dirname, '../../../app/(tabs)/chats.tsx'),
    'utf8',
  );

  test('positions the page title one pixel higher', () => {
    expect(source).toContain('className="-mt-px px-5 pb-3 text-foreground text-H1"');
  });

  test('renders sticky date groups as compact muted badges', () => {
    expect(source).toContain('className="-mx-5 bg-background px-5 py-1"');
    expect(source).toContain('className="self-start rounded-full bg-muted px-3 py-1"');
  });

  test('keeps each date beneath the title until its section is complete', () => {
    expect(source).toContain('<SectionList');
    expect(source).toContain('stickySectionHeadersEnabled');
    expect(source).toContain('renderSectionHeader');
  });
});
