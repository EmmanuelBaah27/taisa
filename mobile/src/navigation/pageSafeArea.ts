import { useSafeAreaInsets } from 'react-native-safe-area-context';

export const PAGE_HEADER_TOP_SPACING = 12;

export function getPageHeaderPaddingTop(topInset: number): number {
  return Math.max(0, topInset) + PAGE_HEADER_TOP_SPACING;
}

export function usePageHeaderPaddingTop(): number {
  const insets = useSafeAreaInsets();
  return getPageHeaderPaddingTop(insets.top);
}
