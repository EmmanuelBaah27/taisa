# SwiftUI Baseline Fixture Harness Design

**Status:** Superseded; React Native fixture work is no longer a native-build prerequisite
**Program:** SwiftUI native rebuild — Program 0 baseline freeze  
**Track:** Platform + Product  
**Owner:** Program 0  

## Purpose

Program 0 must preserve the observable React Native experience before native Apple implementation begins. The parity catalog defines 65 states, but the canonical React Native app cannot currently reproduce many of them deterministically. Error, privacy, lifecycle, accessibility, voice, recovery, rotation, and multitasking states cannot be accepted as baseline evidence when they depend on improvised data or manual timing.

Build a development-only baseline fixture harness that renders the real React Native screens and design-system components against deterministic synthetic services. The harness must make every parity-catalog state repeatable on the reference iPhone and iPad without adding fixture entry points, synthetic data, or alternate behavior to the production Taisa application.

## Success criteria

- Every `PC-NNN` row maps to one executable fixture definition.
- A fixture opens the required route and reaches the declared state deterministically.
- Static states settle to a declared ready condition before capture.
- Motion and lifecycle states expose deterministic start, action, and completion markers.
- The harness uses only synthetic content and cannot contact production services.
- The production Taisa target cannot import, route to, or bundle harness modules.
- The harness runs on the agreed physical iPhone and iPad and supports simulator diagnostics without treating simulator output as physical-device performance evidence.
- Capture output includes the catalog ID, device, OS, viewport, fixture, candidate commit, timestamp, media hash, and batch appearance settings.
- Advancing the canonical candidate revision invalidates stale captures and requires regeneration or explicit re-acceptance.

## Non-goals

- The harness is not a customer-facing demo mode.
- It does not replace unit, integration, snapshot, accessibility, or physical-device tests.
- It does not create production seed data or modify a user's local archive.
- It does not make network-dependent coaching responses part of the baseline.
- It does not define SwiftUI implementation architecture; it records the React Native oracle that SwiftUI must match or explicitly supersede.

## Selected architecture

### Separate application target

Add a dedicated `TaisaBaseline` development target with its own bundle identifier and display name. It shares production presentation modules but owns a separate entry point, route composition, fixture registry, and dependency container. The existing `Taisa` target remains the production application.

The baseline target is selected explicitly by its Xcode scheme and Expo configuration. A public environment flag inside the normal Taisa bundle is not sufficient isolation. The normal target must have no route, gesture, deep link, menu, or runtime switch that enables fixture behavior.

### Dependency boundary

Production screens continue to depend on typed capabilities rather than fixture-specific state. Where a screen currently reaches a singleton directly, introduce the narrowest production interface needed by that screen and inject its current implementation from the Taisa composition root. The baseline composition root supplies deterministic in-memory implementations of the same interfaces.

Presentation modules must not import the fixture registry. Fixture modules may import production domain types and presentation modules. This one-way dependency is enforced by an executable import-boundary check.

```text
Production domain + design system + screens
                    ^
                    |
        typed capability interfaces
           ^                  ^
           |                  |
  Taisa production root   TaisaBaseline root
  real local services     deterministic fixtures
```

### Fixture registry

The registry exposes one record per catalog ID:

```ts
type BaselineDeviceClass = 'iphone' | 'ipad';
type BaselineCaptureKind = 'static' | 'motion';

interface BaselineFixtureDefinition {
  catalogId: `PC-${string}`;
  fixtureId:
    | 'fixture.onboarding.new'
    | 'fixture.home.attention'
    | 'fixture.chats.history'
    | 'fixture.coaching.text'
    | 'fixture.coaching.voice-clear'
    | 'fixture.coaching.voice-uncertain'
    | 'fixture.coaching.voice-no-speech'
    | 'fixture.me.recovery';
  deviceClasses: readonly BaselineDeviceClass[];
  captureKind: BaselineCaptureKind;
  initialRoute: string;
  buildDependencies(): BaselineDependencies;
  readyMarker: string;
  motion?: BaselineMotionScript;
}
```

Catalog IDs are unique and exhaustive. The registry verifier compares the catalog and registry in both directions: missing fixtures, duplicate IDs, unknown IDs, inconsistent fixture names, device requirements, or capture types fail verification.

### Fixture selection

The baseline target accepts a catalog ID through a launch argument or a baseline-only deep link. Unknown, missing, or incompatible IDs render a non-capturable diagnostic screen and emit a machine-readable failure marker. The most recently selected fixture may be retained only inside the baseline app container for operator convenience.

Fixture selection resets the baseline dependency container. No state may leak from one catalog ID to the next.

### Deterministic state model

Each fixture owns a frozen clock, stable identifiers, seeded in-memory repositories, deterministic capability results, and scripted asynchronous transitions. The fixture layer never reads production user data.

- Loading states remain loading until the capture driver releases their gate.
- Error and recovery states return typed fixture failures rather than corrupting a database.
- Coaching streams use a fixed sequence of chunks and timestamps.
- Voice outcomes use bundled synthetic audio descriptors and scripted transcript events. No fixture requires recording a person's voice.
- Privacy and app-lifecycle fixtures use a typed baseline guard adapter. They do not weaken the production privacy guard.
- Notification, export, restore, and authentication fixtures model results in memory and never schedule notifications, create archives outside the baseline sandbox, or invoke biometric enrollment.
- Motion fixtures define named actions and completion markers rather than relying on arbitrary delays.

## Capture protocol

### Readiness contract

The baseline root exposes machine-readable markers in development logs and the accessibility tree:

- `baseline:booting:<PC-NNN>`
- `baseline:ready:<PC-NNN>`
- `baseline:motion-start:<PC-NNN>`
- `baseline:motion-complete:<PC-NNN>`
- `baseline:error:<PC-NNN>:<code>`

Static capture begins only after `ready`. Motion capture begins immediately before the named action and ends after `motion-complete`. Timeouts are failures and do not produce accepted media.

### Files and metadata

Repository media uses:

- `PC-NNN__iphone__state.png`
- `PC-NNN__iphone__motion.mov`
- `PC-NNN__ipad__state.png`
- `PC-NNN__ipad__motion.mov`

Every manifest record contains:

```ts
interface BaselineMediaRecord {
  catalogId: `PC-${string}`;
  path: string;
  sha256: string;
  device: string;
  os: string;
  viewport: string;
  commit: string;
  fixture: string;
  capturedAt: string;
  batchId: string;
  appearance: {
    colorScheme: 'light' | 'dark';
    contentSizeCategory: string;
    reduceMotion: boolean;
    increaseContrast: boolean;
    reduceTransparency: boolean;
    voiceOver: boolean;
  };
}
```

The batch record also names the Xcode version, baseline target build number, Metro host revision, and physical device identifiers. Personal content and secrets are forbidden.

### Storage limits

Each committed file must be at most 10 MB and committed reference media must remain at most 100 MB in total. A larger required artifact may use a durable Baah-approved location, but the manifest must retain its SHA-256 and resolvable location. An unavailable external artifact fails verification.

## Production isolation

Isolation is a release-blocking property.

- The production Expo/Xcode configuration names only the normal entry point and bundle identifier.
- Production route enumeration contains no baseline route.
- The production dependency graph contains no module under the baseline fixture root.
- Production bundles contain no fixture IDs, readiness markers, synthetic profile content, or baseline deep-link scheme.
- Baseline adapters reject non-loopback API configuration and do not initialize the production coaching gateway.
- CI builds both targets, then scans the production bundle and route graph for forbidden baseline symbols.
- A failed isolation check prevents integration into `preview/taisa`.

The baseline target may be distributed only as a locally signed development build. It is not uploaded to TestFlight or an app store.

## Accessibility and platform behavior

Fixtures do not bypass platform settings. Dynamic Type, VoiceOver, increased contrast, reduced transparency, and reduced motion rows are captured with the corresponding system setting enabled and recorded in the batch metadata.

iPad fixtures cover full-screen landscape, keyboard changes, modal or popover presentation, rotation, and supported multitasking widths. Simulator captures may diagnose layout, but physical iPad evidence remains required for baseline acceptance and performance measurements.

## Performance evidence

Performance measurements use a Release configuration of the production Taisa target, not the baseline target, because fixture instrumentation would distort results. Synthetic local data is loaded through a controlled test archive or release-safe setup procedure documented in the performance record.

At least five runs on each reference device record cold and warm launch, memory, database operations, scrolling and navigation frame stability, recording readiness, transcription-to-coaching milestones, installed size, and exported archive size. Raw observations, median, worst case, tooling, device state, thermal state, and caveats are retained. Program 1 proposes thresholds; Program 0 records the reference distribution.

## Candidate revision and integration

The harness is implemented on an isolated feature branch based on the current canonical candidate. Product behavior changes discovered while making states reproducible are not silently folded into the harness. Each behavior defect is handled through the Taisa bug loop and verified separately.

After tests and production-isolation checks pass:

1. Integrate the harness commit into `preview/taisa` without unrelated feature work.
2. Push and confirm the exact revision served by the canonical preview runtime.
3. Regenerate the source and route manifests against that revision.
4. Reconcile any catalog/source changes.
5. Rebuild both physical-device apps.
6. Capture and hash every catalog row.
7. Run performance measurement on release production builds.
8. Request Baah's baseline-freeze approval.

No media from commit `719180012de745e3b507ed93eadbe7d8a951331c` is accepted after the candidate advances unless its manifest record is explicitly revalidated against unchanged source and behavior.

## Error handling

- Unknown or incomplete fixture: block capture and report the registry error.
- Fixture timeout: retain logs, discard media, and diagnose the stalled capability.
- Unexpected network attempt: fail the fixture immediately and record the attempted destination without sending content.
- Production isolation failure: stop integration; never waive it through manifest editing.
- Device disconnect or appearance-setting drift: end the batch and start a new batch after reconnection.
- App crash or native exception: preserve crash evidence, enter the normal bug loop, and recapture affected rows after the fix.
- Candidate revision mismatch: refuse capture and require a rebuild from the canonical revision.

## Verification strategy

### Automated

- Registry/catalog bijection and schema tests.
- Fixture determinism tests using two independent constructions of every fixture.
- State-transition tests for loading, errors, coaching, voice outcomes, privacy, recovery, and motion markers.
- Network-denial tests proving baseline adapters cannot reach external services.
- Reset tests proving state does not leak between fixture selections.
- Production import, route, bundle-string, scheme, and target-membership isolation tests.
- Capture-manifest metadata, hash, size, filename, commit, and appearance validation.
- Full existing React Native test and type-check suites.

### Physical devices

- Install separately signed Taisa and TaisaBaseline builds on the reference iPhone and iPad.
- Verify the normal Taisa app has no fixture affordance or baseline URL handling.
- Execute every required fixture and capture only after its readiness marker.
- Run accessibility-specific fixtures with their declared system settings.
- Run release performance measurement on the production target.

## Documentation changes

The implementation updates:

- the Program 0 implementation plan and execution ledger;
- the parity catalog and reference-media protocol;
- the baseline capture and verification scripts;
- canonical preview/build instructions;
- the program ledger with the new candidate revision;
- the final baseline manifest, media manifest, performance record, and closeout evidence.

## Approval gates

This design approval authorizes writing the detailed implementation plan. The revised plan requires Baah review before product code changes. After implementation and evidence capture, Baah separately approves the baseline freeze. Ship approval remains separate from baseline-freeze approval.
