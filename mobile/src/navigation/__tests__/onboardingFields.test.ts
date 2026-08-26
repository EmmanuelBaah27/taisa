import * as Crypto from 'expo-crypto';

import { Field, generateLocalProfileId } from '../../../app/onboarding';
import { Input } from '../../components/ui/Input';

describe('onboarding fields', () => {
  test('forwards typed text to the controlled form callback', () => {
    const onChange = jest.fn();
    const field = Field({ label: 'Current role', value: '', onChange });
    const input = field.props.children;

    expect(input.type).toBe(Input);
    expect(input.props.label).toBe('Current role');
    expect(input.props.onChangeText).toBe(onChange);
    input.props.onChangeText('Product designer');
    expect(onChange).toHaveBeenCalledWith('Product designer');
  });

  test('creates the local profile ID through the native Expo crypto boundary', () => {
    jest.spyOn(Crypto, 'randomUUID').mockReturnValueOnce('11111111-1111-4111-8111-111111111111');
    expect(generateLocalProfileId()).toBe('11111111-1111-4111-8111-111111111111');
    expect(Crypto.randomUUID).toHaveBeenCalledTimes(1);
  });
});
