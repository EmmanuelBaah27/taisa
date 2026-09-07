export async function DynamicField() {
  const RN = await import('react-native');
  const Field = RN.TextInput;
  return <Field />;
}
