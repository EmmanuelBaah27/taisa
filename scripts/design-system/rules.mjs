export const RULES = [
  {
    id: 'no-raw-color',
    message: 'Use a semantic color role instead of a raw color value.',
    pattern: /#[0-9A-Fa-f]{3,8}\b|\brgba?\([^)]*\)|\bhsla?\([^)]*\)|\boklch\([^)]*\)/g,
  },
  {
    id: 'semantic-text-only',
    message: 'Product copy must use the design-system Text component.',
    pattern: /import\s*\{[^}]*\bText\b[^}]*\}\s*from\s*['"]react-native['"]/g,
  },
  {
    id: 'no-legacy-type',
    message: 'Use a semantic typography role instead of legacy size or weight styling.',
    pattern: /\btext-(?:xs|sm|base|lg|xl|\[[^\]]+\])\b|\bfont-(?:normal|medium|semibold|bold)\b|\bfont(?:Size|Weight)\s*:/g,
  },
  {
    id: 'no-stylesheet-create',
    message: 'Use NativeWind and semantic components instead of StyleSheet.create().',
    pattern: /\bStyleSheet\.create\s*\(/g,
  },
];

export const PRODUCT_EXTENSIONS = new Set(['.ts', '.tsx', '.js', '.jsx', '.css', '.json']);
