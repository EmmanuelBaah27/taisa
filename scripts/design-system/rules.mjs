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
  {
    id: 'prohibited-screen-primitives',
    message: 'Product screens must use design-system action and field primitives.',
    productScreensOnly: true,
    pattern: /(?:import\s*\{[^}]*(?:Pressable|TouchableOpacity|TextInput|Switch)[^}]*\}\s*from\s*['"]react-native['"]|import\s+(?:\*\s+as\s+)?([A-Za-z_$][\w$]*)\s+from\s*['"]react-native['"][\s\S]*?\1\.(?:Pressable|TouchableOpacity|TextInput|Switch)\b|(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*require\s*\(\s*['"]react-native['"]\s*\)[\s\S]*?\2\.(?:Pressable|TouchableOpacity|TextInput|Switch)\b|(?:const|let|var)\s*\{[^}]*(?:Pressable|TouchableOpacity|TextInput|Switch)[^}]*\}\s*=\s*require\s*\(\s*['"]react-native['"]\s*\))/g,
  },
];

export const PRODUCT_EXTENSIONS = new Set(['.ts', '.tsx', '.js', '.jsx', '.css', '.json']);
