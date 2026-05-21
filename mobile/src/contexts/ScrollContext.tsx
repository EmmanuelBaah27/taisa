import { createContext, useCallback, useContext, useState } from 'react';

interface ScrollContextValue {
  isScrolled: boolean;
  reportScroll: (offset: number) => void;
}

const ScrollContext = createContext<ScrollContextValue>({
  isScrolled: false,
  reportScroll: () => {},
});

export function ScrollProvider({ children }: { children: React.ReactNode }) {
  const [isScrolled, setIsScrolled] = useState(false);

  const reportScroll = useCallback((offset: number) => {
    setIsScrolled(offset > 4);
  }, []);

  return (
    <ScrollContext.Provider value={{ isScrolled, reportScroll }}>
      {children}
    </ScrollContext.Provider>
  );
}

export const useScrollContext = () => useContext(ScrollContext);
