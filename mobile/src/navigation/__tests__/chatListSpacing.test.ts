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

  test('gives date labels two pixels of vertical padding', () => {
    expect(source).toContain(
      'className="-mx-5 bg-background px-5 py-[2px] text-muted-foreground text-small-regular"',
    );
  });

  test('keeps each date beneath the title until its section is complete', () => {
    expect(source).toContain('<SectionList');
    expect(source).toContain('stickySectionHeadersEnabled');
    expect(source).toContain('renderSectionHeader');
  });
});
