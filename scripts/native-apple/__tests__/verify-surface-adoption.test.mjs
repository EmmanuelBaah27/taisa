import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import * as verifier from '../verify-design-system.mjs';

async function fixture(t, files) {
  const root = await mkdtemp(path.join(os.tmpdir(), 'taisa-surface-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  await mkdir(path.join(root, 'apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem'), { recursive: true });
  for (const [file, source] of Object.entries(files)) {
    const target = path.join(root, file);
    await mkdir(path.dirname(target), { recursive: true });
    await writeFile(target, source);
  }
  return root;
}

const product = 'apple/TaisaApp/You/YouView.swift';
const ds = 'apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem';
const audit = async (root) => {
  assert.equal(typeof verifier.surfaceAdoptionViolations, 'function', 'whole-surface adoption audit must exist');
  return verifier.surfaceAdoptionViolations({ repositoryRoot: root, productFiles: [product] });
};

test('unannotated Product text cannot hide behind inherited fonts', async (t) => {
  const root = await fixture(t, { [product]: 'struct YouView: View { var body: some View { Text("Backup") } }' });
  const violations = await audit(root);
  assert.ok(violations.some(v => v.kind === 'implicit-product-presentation' && v.constructor === 'Text'));
});

test('audit follows shared component dependencies to catch system-font tokens', async (t) => {
  const root = await fixture(t, {
    [product]: 'struct YouView: View { var body: some View { TaisaButton() } }',
    [`${ds}/TaisaButton.swift`]: 'public struct TaisaButton: View { var body: some View { TaisaText(role: .label) } }',
    [`${ds}/TaisaText.swift`]: 'public struct TaisaText: View { var body: some View { Text("Go").font(TaisaTypography.label.font) } }',
    [`${ds}/TypographyToken.swift`]: 'public enum TaisaTypography { var font: Font { .system(.body) } }',
  });
  assert.ok((await audit(root)).some(v => v.kind === 'system-font-token'));
});

test('shared components cannot introduce an undeclared font directly', async (t) => {
  const root = await fixture(t, {
    [product]: 'struct YouView: View { var body: some View { TaisaCard() } }',
    [`${ds}/TaisaCard.swift`]: 'public struct TaisaCard: View { var body: some View { Text("Go").font(.headline) } }',
  });
  assert.ok((await audit(root)).some(v => v.kind === 'raw-shared-typography'));
});

test('explicit DS text and token-owned custom fonts pass; comments and strings are ignored', async (t) => {
  const root = await fixture(t, {
    [product]: 'struct YouView: View { var body: some View { TaisaText(content: "Text( and .font(.system)") } } // Button("Fake") {}',
    [`${ds}/TaisaText.swift`]: 'public struct TaisaText: View { var body: some View { Text("Go").font(TaisaTypography.body.font) } }',
    [`${ds}/TypographyToken.swift`]: 'public enum TaisaTypography { var font: Font { .custom("Inter", size: 16) } }',
  });
  assert.deepEqual(await audit(root), []);
});

test('reviewed You surface has no implicit text/control presentation or shared font fallback', async () => {
  const violations = await audit(process.cwd());
  assert.deepEqual(violations, []);
  const source = await readFile(product, 'utf8');
  assert.match(source, /TaisaButton\(role: \.secondary, label: "Open backup and recovery"/);
});

test('changed surfaces must retire legacy debt instead of refreshing its fingerprint', () => {
  assert.equal(typeof verifier.legacyDebtRetirementViolations, 'function');
  const debt = { file: product, constructor: 'Button', owner: 'APF-75' };
  assert.deepEqual(verifier.legacyDebtRetirementViolations([debt], [product]), [
    { kind: 'changed-surface-legacy-debt', ...debt },
  ]);
  assert.deepEqual(verifier.legacyDebtRetirementViolations([debt], ['apple/TaisaApp/Other.swift']), []);
});

test('new and pre-existing changed Product sources enter the audit automatically', () => {
  assert.equal(typeof verifier.auditedProductFiles, 'function');
  assert.deepEqual(verifier.auditedProductFiles([product], [
    product, 'apple/TaisaApp/NewScreen.swift', 'apple/TaisaApp/ExistingSystemScreen.swift',
    'apple/TaisaUnitTests/Test.swift',
  ]), [product, 'apple/TaisaApp/NewScreen.swift', 'apple/TaisaApp/ExistingSystemScreen.swift']);
});

test('raw text inside a composite DS wrapper still requires the shared text primitive', async (t) => {
  const root = await fixture(t, {
    [product]: 'struct YouView: View { var body: some View { TaisaCard() } }',
    [`${ds}/TaisaCard.swift`]: 'public struct TaisaCard: View { var body: some View { Text("Go") } }',
  });
  assert.ok((await audit(root)).some(v => v.kind === 'implicit-shared-presentation'));
});

test('system-control string labels cannot escape semantic text adoption', async (t) => {
  const root = await fixture(t, {
    [product]: 'struct YouView: View { var body: some View { ProgressView("Loading You") } }',
  });
  assert.ok((await audit(root)).some(v => v.kind === 'implicit-product-presentation' && v.constructor === 'ProgressView'));
});

test('qualified and backticked raw shared text cannot bypass adoption', async (t) => {
  const root = await fixture(t, {
    [product]: 'struct YouView: View { var body: some View { TaisaCard() } }',
    [`${ds}/TaisaCard.swift`]: 'public struct TaisaCard: View { var body: some View { SwiftUI.`Text`.init("Go") } }',
  });
  assert.ok((await audit(root)).some(v => v.kind === 'implicit-shared-presentation'));
});

test('changed shared components are audited before any screen consumes them', async (t) => {
  const file = `${ds}/TaisaNewCard.swift`;
  const root = await fixture(t, {
    [product]: 'struct YouView: View { var body: some View { EmptyView() } }',
    [file]: 'public struct TaisaNewCard: View { var body: some View { Text("Go") } }',
  });
  assert.equal(typeof verifier.surfaceAdoptionViolations, 'function');
  const violations = await verifier.surfaceAdoptionViolations({ repositoryRoot: root, productFiles: [product], sharedSourceFiles: [file] });
  assert.ok(violations.some(v => v.kind === 'implicit-shared-presentation'));
});

test('Product modifiers cannot override a shared component with a raw font', async (t) => {
  const root = await fixture(t, {
    [product]: 'struct YouView: View { var body: some View { TaisaText(content: "Go").font(.headline) } }',
    [`${ds}/TaisaText.swift`]: 'public struct TaisaText: View { var body: some View { Text("Go").font(TaisaTypography.body.font) } }',
    [`${ds}/TypographyToken.swift`]: 'public enum TaisaTypography { var font: Font { .custom("Inter", size: 16) } }',
  });
  assert.ok((await audit(root)).some(v => v.kind === 'raw-product-typography'));
});

test('generated system headers and unavailable states must declare their DS treatment', async (t) => {
  const root = await fixture(t, {
    [product]: 'struct YouView: View { var body: some View { Section("Recovery") { ContentUnavailableView("Unavailable", systemImage: "cloud") } } }',
  });
  assert.equal((await audit(root)).filter(v => v.kind === 'implicit-product-presentation').length, 2);
});

test('system labels passed through variables or qualified initializers cannot bypass adoption', async (t) => {
  const root = await fixture(t, {
    [product]: 'struct YouView: View { let title = "Loading"; var body: some View { ProgressView(title); SwiftUI.`Section`.init(title) { EmptyView() } } }',
  });
  const violations = (await audit(root)).filter(v => v.kind === 'implicit-product-presentation');
  assert.deepEqual(violations.map(v => v.constructor).sort(), ['ProgressView', 'Section']);
});

test('unlabelled progress and explicit semantic label closures remain available', async (t) => {
  const root = await fixture(t, {
    [product]: 'struct YouView: View { var body: some View { ProgressView(); ProgressView(value: 0.5); Section { EmptyView() } header: { TaisaText(content: "Recovery") }; Toggle(isOn: $enabled) { TaisaText(content: "Enabled") } } }',
  });
  assert.deepEqual(await audit(root), []);
});


test('native menu text exemption is confined to its named adapter', async (t) => {
  const file = `${ds}/TaisaButtonControl.swift`;
  const adapter = `public func TaisaSystemIconButton(_ title: String) -> Button<Label<Text, Image>> {
    Button { Label { Text(title) } icon: { Image(systemName: "copy") } }
}`;
  const root = await fixture(t, {
    [product]: 'struct YouView: View { var body: some View { TaisaButtonControl() } }',
    [file]: 'struct TaisaButtonControl: View {}\n' + adapter,
  });
  assert.deepEqual(await audit(root), []);
  await writeFile(path.join(root, file), 'struct TaisaButtonControl: View { var body: some View { Text("Unowned") } }\n' + adapter);
  assert.ok((await audit(root)).some(v => v.kind === 'implicit-shared-presentation'));
});

test('Text return and property types are not mistaken for construction', async (t) => {
  const root = await fixture(t, {
    [product]: 'func message() -> Text { TaisaText.native("Hello") }; var rendered: Text { TaisaText.native("Hello") }',
  });
  assert.deepEqual(await audit(root), []);
});
