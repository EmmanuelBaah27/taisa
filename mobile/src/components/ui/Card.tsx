import React from 'react';
import { View, Text, type ViewStyle } from 'react-native';

export type CardSurface = 'default' | 'elevated';

export interface CardProps {
  surface?: CardSurface;
  children: React.ReactNode;
  className?: string;
  style?: ViewStyle;
}

const SURFACE_CLASS: Record<CardSurface, string> = {
  default:  'bg-card rounded-xl border border-border-light',
  elevated: 'bg-card rounded-2xl border border-border-strong',
};

const SURFACE_SHADOW: Record<CardSurface, ViewStyle> = {
  default: {
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.05,
    shadowRadius: 2,
    elevation: 1,
  },
  elevated: {
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.08,
    shadowRadius: 8,
    elevation: 3,
  },
};

export function Card({ surface = 'default', children, className = '', style }: CardProps) {
  return (
    <View
      className={[SURFACE_CLASS[surface], className].filter(Boolean).join(' ')}
      style={[SURFACE_SHADOW[surface], style]}
    >
      {children}
    </View>
  );
}

export interface CardHeaderProps {
  children: React.ReactNode;
  className?: string;
}

export function CardHeader({ children, className = '' }: CardHeaderProps) {
  return (
    <View className={['p-6 gap-1.5', className].filter(Boolean).join(' ')}>
      {children}
    </View>
  );
}

export interface CardTitleProps {
  children: React.ReactNode;
  className?: string;
}

export function CardTitle({ children, className = '' }: CardTitleProps) {
  return (
    <Text className={['text-lg font-semibold text-foreground leading-none', className].filter(Boolean).join(' ')}>
      {children}
    </Text>
  );
}

export interface CardDescriptionProps {
  children: React.ReactNode;
  className?: string;
}

export function CardDescription({ children, className = '' }: CardDescriptionProps) {
  return (
    <Text className={['text-sm text-muted-foreground', className].filter(Boolean).join(' ')}>
      {children}
    </Text>
  );
}

export interface CardContentProps {
  children: React.ReactNode;
  className?: string;
}

export function CardContent({ children, className = '' }: CardContentProps) {
  return (
    <View className={['px-6 pb-6', className].filter(Boolean).join(' ')}>
      {children}
    </View>
  );
}

export interface CardFooterProps {
  children: React.ReactNode;
  className?: string;
  style?: import('react-native').ViewStyle;
}

export function CardFooter({ children, className = '', style }: CardFooterProps) {
  return (
    <View style={style} className={['flex-row items-center px-6 pb-6', className].filter(Boolean).join(' ')}>
      {children}
    </View>
  );
}
