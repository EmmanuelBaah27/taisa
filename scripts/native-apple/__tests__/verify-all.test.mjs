import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { chmod, mkdir, mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { delimiter, join, resolve } from 'node:path';
import test from 'node:test';

const repositoryRoot = resolve(import.meta.dirname, '../../..');

test('combined verification boots a simulator before clearing retained app state', async () => {
  const fixture = await mkdtemp(join(tmpdir(), 'taisa-native-verifier-'));
  const bin = join(fixture, 'bin');
  const log = join(fixture, 'simctl.log');
  await mkdir(bin);

  const commands = {
    bash: '#!/bin/sh\nexit 0\n',
    npm: '#!/bin/sh\nexit 0\n',
    swift: '#!/bin/sh\nexit 0\n',
    node: '#!/bin/sh\nif [ "$1" = "scripts/native-apple/select-simulator.mjs" ]; then if [ "$2" = "--eligible" ]; then printf "yes\\n"; else printf "iPhone 17 Pro\\n"; fi; else exit 0; fi\n',
    xcodebuild: '#!/bin/sh\nif printf "%s\\n" "$@" | grep -q -- -showdestinations; then printf "iOS Simulator\\n"; exit 0; fi\nif [ "${TAISA_TEST_REQUIRE_XCODE_RETRY:-0}" = "1" ] && printf "%s\\n" "$@" | grep -q "^test$" && ! printf "%s\\n" "$@" | grep -q -- -retry-tests-on-failure; then exit 65; fi\nexit 0\n',
    xcrun: `#!/bin/sh
if [ "$1" != "simctl" ]; then exit 0; fi
shift
printf '%s\\n' "$*" >> "$TAISA_TEST_SIMCTL_LOG"
case "$1" in
  list) printf '{"devices":{}}\\n' ;;
  boot) : > "$TAISA_TEST_SIMULATOR_BOOTED" ;;
  bootstatus) sleep "\${TAISA_TEST_BOOTSTATUS_DELAY:-0}"; test -f "$TAISA_TEST_SIMULATOR_BOOTED" ;;
  uninstall) test -f "$TAISA_TEST_SIMULATOR_BOOTED" ;;
esac
`,
  };

  for (const [name, source] of Object.entries(commands)) {
    const path = join(bin, name);
    await writeFile(path, source);
    await chmod(path, 0o755);
  }

  execFileSync('/bin/bash', ['scripts/native-apple/verify-all.sh'], {
    cwd: repositoryRoot,
    env: {
      ...process.env,
      PATH: `${bin}${delimiter}${process.env.PATH}`,
      TAISA_NATIVE_ARTIFACTS: join(fixture, 'artifacts'),
      TAISA_TEST_SIMCTL_LOG: log,
      TAISA_TEST_SIMULATOR_BOOTED: join(fixture, 'booted'),
    },
  });

  const calls = (await readFile(log, 'utf8')).trim().split('\n');
  const boot = calls.findIndex((call) => call.startsWith('boot '));
  const bootstatus = calls.findIndex((call) => call.startsWith('bootstatus '));
  const uninstall = calls.findIndex((call) => call.includes('uninstall') && call.includes('com.taisa.app.dev'));
  assert.ok(boot >= 0, 'the verifier must boot the selected simulator');
  assert.ok(bootstatus > boot, 'the verifier must wait for the simulator to finish booting');
  assert.ok(uninstall > bootstatus, 'the verifier must clear app state only after the simulator is booted');

  const startedAt = Date.now();
  assert.throws(() => execFileSync('/bin/bash', ['scripts/native-apple/verify-all.sh'], {
    cwd: repositoryRoot,
    env: {
      ...process.env,
      PATH: `${bin}${delimiter}${process.env.PATH}`,
      TAISA_NATIVE_ARTIFACTS: join(fixture, 'timeout-artifacts'),
      TAISA_SIMULATOR_BOOT_TIMEOUT_SECONDS: '1',
      TAISA_TEST_BOOTSTATUS_DELAY: '3',
      TAISA_TEST_SIMCTL_LOG: log,
      TAISA_TEST_SIMULATOR_BOOTED: join(fixture, 'booted'),
    },
  }));
  assert.ok(Date.now() - startedAt < 5_000, 'a stuck simulator boot must fail within its configured bound');

  assert.doesNotThrow(() => execFileSync('/bin/bash', ['scripts/native-apple/verify-all.sh'], {
    cwd: repositoryRoot,
    env: {
      ...process.env,
      PATH: `${bin}${delimiter}${process.env.PATH}`,
      TAISA_NATIVE_ARTIFACTS: join(fixture, 'retry-artifacts'),
      TAISA_TEST_REQUIRE_XCODE_RETRY: '1',
      TAISA_TEST_SIMCTL_LOG: log,
      TAISA_TEST_SIMULATOR_BOOTED: join(fixture, 'booted'),
    },
  }), 'simulator test lanes must retry transient Xcode test failures');
});
