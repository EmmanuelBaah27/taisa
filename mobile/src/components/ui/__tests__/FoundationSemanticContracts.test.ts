import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

function source(name: string) {
  return readFileSync(resolve(__dirname, `../${name}.tsx`), 'utf8');
}

describe('foundation semantic contracts', () => {
  test.each(['Button', 'Input', 'Card', 'Badge'])(
    '%s renders copy through semantic Text',
    (name) => {
      const contents = source(name);
      expect(contents).toContain("from './Text'");
      expect(contents).not.toMatch(/import \{[^}]*\bText\b[^}]*\} from 'react-native'/);
    },
  );

  test('Input exposes semantic label, helper, and error messaging', () => {
    const contents = source('Input');
    expect(contents).toContain('label?: string');
    expect(contents).toContain('helperText?: string');
    expect(contents).toContain('errorMessage?: string');
  });

  test('Icon exposes a semantic Product color role', () => {
    const contents = source('Icon');
    expect(contents).toContain('colorRole?: IconColorRole');
    expect(contents).toContain('iconColorValues[colorRole]');
  });
});
