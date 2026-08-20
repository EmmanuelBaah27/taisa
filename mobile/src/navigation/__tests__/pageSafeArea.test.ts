import { getPageHeaderPaddingTop } from '../pageSafeArea';

describe('page header safe area', () => {
  test('places the title below the status bar with the standard header spacing', () => {
    expect(getPageHeaderPaddingTop(47)).toBe(59);
  });

  test('does not allow an invalid negative inset to pull the title upward', () => {
    expect(getPageHeaderPaddingTop(-10)).toBe(12);
  });
});
