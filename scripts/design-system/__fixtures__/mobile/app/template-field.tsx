export async function TemplateField() {
  const RN = await import(`react-native`);
  return <RN.TextInput />;
}
