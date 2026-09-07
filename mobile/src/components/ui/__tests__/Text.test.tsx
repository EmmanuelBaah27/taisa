import { Text, textAlignmentClasses, textColorClasses, typographyRoleClasses } from '../Text';

describe('semantic Text', () => {
  it('defaults to readable body copy and primary text', () => {
    const element = Text({ children: 'Readable by default' });
    expect(element.props.className).toBe('text-body text-foreground');
    expect(element.props.allowFontScaling).toBeUndefined();
  });

  it('maps every approved typography and color role through closed records', () => {
    expect(Object.keys(typographyRoleClasses)).toEqual(['display', 'heading', 'subheading', 'body', 'bodyStrong', 'label', 'labelStrong', 'metadata', 'metadataStrong']);
    expect(Object.keys(textColorClasses)).toEqual(['primary', 'secondary', 'tertiary', 'inverted', 'disabled', 'success', 'warning', 'danger', 'info']);
  });

  it('forwards text behavior without disabling accessibility scaling', () => {
    const element = Text({ children: 'Two lines', numberOfLines: 2, selectable: true });
    expect(element.props.numberOfLines).toBe(2);
    expect(element.props.selectable).toBe(true);
    expect(element.props.allowFontScaling).toBeUndefined();
  });

  it('supports only closed semantic alignment choices', () => {
    expect(textAlignmentClasses).toEqual({ left: 'text-left', center: 'text-center', right: 'text-right' });
    expect(Text({ children: 'Centered', align: 'center' }).props.className).toBe('text-body text-foreground text-center');
  });
});

// @ts-expect-error Semantic Text does not expose arbitrary visual styles.
Text({ children: 'No escape hatch', style: { fontSize: 11 } });
// @ts-expect-error Semantic Text does not expose arbitrary class overrides.
Text({ children: 'No escape hatch', className: 'text-[11px] font-bold' });
