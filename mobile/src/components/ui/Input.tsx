import React, { useState } from 'react';
import { TextInput, View, type TextInputProps, type ViewStyle } from 'react-native';
import { colorTokens } from '../../design-system/tokens';
import { Text } from './Text';

export type InputSize = 'default' | 'lg';

export interface InputProps extends Omit<TextInputProps, 'style'> {
  size?: InputSize;
  /** Renders error border */
  error?: boolean;
  label?: string;
  helperText?: string;
  errorMessage?: string;
  style?: ViewStyle;
}

const SIZE_HEIGHT: Record<InputSize, string> = {
  default: 'h-[40px]',
  lg:      'h-[44px]',
};

const SIZE_TEXT: Record<InputSize, string> = {
  default: 'text-body',
  lg:      'text-body',
};

export function Input({
  size = 'default',
  error = false,
  label,
  helperText,
  errorMessage,
  editable = true,
  style,
  ...props
}: InputProps) {
  const [focused, setFocused] = useState(false);
  const isDisabled = editable === false;
  const hasError = error || Boolean(errorMessage);

  const borderClass = (() => {
    if (isDisabled) return 'border-border-light';
    if (hasError && focused) return 'border-danger';
    if (hasError) return 'border-danger-border';
    if (focused) return 'border-border-strong';
    return 'border-border-light';
  })();

  const containerClass = [
    'w-full rounded-xl border px-3 flex-row items-center',
    'bg-card',
    SIZE_HEIGHT[size],
    borderClass,
    isDisabled ? 'opacity-50 bg-muted' : '',
  ]
    .filter(Boolean)
    .join(' ');

  return (
    <View className="w-full gap-1.5">
      {label ? <Text role="labelStrong">{label}</Text> : null}
      <View className={containerClass} style={style}>
        <TextInput
          className={['flex-1 text-foreground', SIZE_TEXT[size]].join(' ')}
          placeholderTextColor={colorTokens.text.tertiary}
          editable={!isDisabled}
          onFocus={(e) => {
            setFocused(true);
            props.onFocus?.(e);
          }}
          onBlur={(e) => {
            setFocused(false);
            props.onBlur?.(e);
          }}
          {...props}
        />
      </View>
      {errorMessage ? <Text role="label" color="danger">{errorMessage}</Text> : null}
      {!errorMessage && helperText ? <Text role="label" color="secondary">{helperText}</Text> : null}
    </View>
  );
}
