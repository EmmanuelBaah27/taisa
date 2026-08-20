import fs from 'node:fs';
import path from 'node:path';

describe('Chats list spacing', () => {
  const source = fs.readFileSync(
    path.resolve(__dirname, '../../../app/(tabs)/chats.tsx'),
    'utf8',
  );
  const homeSource = fs.readFileSync(
    path.resolve(__dirname, '../../../app/(tabs)/index.tsx'),
    'utf8',
  );

  test('positions the page title one pixel higher', () => {
    expect(source).toContain('className="-mt-px px-5 pb-3 text-foreground text-H1"');
  });

  test('renders sticky date groups as compact muted badges', () => {
    expect(source).toContain('className="-mx-5 bg-background px-5 py-1"');
    expect(source).toContain('className="self-start rounded-full bg-muted px-3 py-1"');
    expect(source).not.toMatch(/text-caption-semibold uppercase/);
  });

  test('keeps each date beneath the title until its section is complete', () => {
    expect(source).toContain('<SectionList');
    expect(source).toContain('stickySectionHeadersEnabled');
    expect(source).toContain('renderSectionHeader');
  });

  test('renders the Home date-group heading in sentence case', () => {
    expect(homeSource).not.toMatch(/text-xs font-bold uppercase tracking-wider mb-3/);
  });

  test('places main-page content beneath the shared translucent headers', () => {
    expect(homeSource).toContain("getPageHeaderScrollInset(pageHeaderPaddingTop, 'workspace') + 8");
    expect(source).toContain("getPageHeaderScrollInset(pageHeaderPaddingTop, 'title')");
    expect(source).toContain('<PageHeaderSurface');
  });
});
