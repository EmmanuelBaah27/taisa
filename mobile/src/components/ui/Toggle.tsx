import { Switch } from 'react-native';

import { colorTokens } from '../../design-system/tokens';

export interface ToggleProps {
  label: string;
  value: boolean;
  disabled?: boolean;
  onValueChange: (value: boolean) => void;
}

export function Toggle({ label, value, disabled = false, onValueChange }: ToggleProps) {
  return (
    <Switch
      accessibilityLabel={label}
      accessibilityRole="switch"
      accessibilityState={{ checked: value, disabled }}
      value={value}
      disabled={disabled}
      onValueChange={onValueChange}
      trackColor={{ false: colorTokens.action.disabled, true: colorTokens.action.primary }}
      thumbColor={colorTokens.surface.elevated}
    />
  );
}
