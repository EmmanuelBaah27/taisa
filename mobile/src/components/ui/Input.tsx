import React, { useState } from 'react';
import { TextInput, View, type TextInputProps, type ViewStyle } from 'react-native';

export type InputSize = 'default' | 'lg';

export interface InputProps extends Omit<TextInputProps, 'style'> {
  size?: InputSize;
  /** Renders error border */
  error?: boolean;
  style?: ViewStyle;
}

const SIZE_HEIGHT: Record<InputSize, string> = {
  default: 'h-[40px]',
  lg:      'h-[44px]',
};

const SIZE_TEXT: Record<InputSize, string> = {
  default: 'text-sm',
  lg:      'text-base',
};

export function Input({
  size = 'default',
  error = false,
  editable = true,
  style,
  ...props
}: InputProps) {
  const [focused, setFocused] = useState(false);
  const isDisabled = editable === false;

  const borderClass = (() => {
    if (isDisabled) return 'border-border-light';
    if (error && focused) return 'border-danger';
    if (error) return 'border-danger-border';
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
    <View className={containerClass} style={style}>
      <TextInput
        className={[
          'flex-1 text-foreground',
          SIZE_TEXT[size],
        ].join(' ')}
        placeholderTextColor="#737373"
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
  );
}
