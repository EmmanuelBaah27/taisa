# Native encrypted sync CloudKit schema

**Local Task 7 status (2026-10-06):** Code, generated project settings, and entitlement
files declare the approved development and production capabilities. Apple Developer
and CloudKit Console capability state has not been directly verified in this task.
No production schema promotion has been performed or authorized.

## Environments

| App | Bundle ID | Private CloudKit container | Push entitlement |
|---|---|---|---|
| Development | `com.taisa.app.dev` | `iCloud.com.taisa.app.dev` | development |
| Production | `com.taisa.app` | `iCloud.com.taisa.app` | production |
| Preview | `com.taisa.app.preview` | none; deterministic fake only | none |
| Personal | `com.taisa.app.personal` | none; local-only encrypted store plus deliberate encrypted file transfer | none |

The Preview target has an empty entitlements file and does not link
`TaisaCloudKit`. There is no Associated Domains entitlement. Recovery-key
saving uses the approved manual Passwords flow until Baah supplies an owned
HTTPS domain and separately approves Web Credentials integration.

The Personal target also has an empty capability set and does not link
`TaisaCloudKit`. Signed-device QA on 2026-10-06 verified no iCloud, CloudKit,
push, Associated Domains, background-mode, or live-transport linkage in the
signed product. Files/AirDrop recovery is a replace operation between devices,
not a synchronization transport and not a CloudKit acceptance substitute.

## Development schema proposal

`CKSyncEngine` uses the private database and custom zone `TaisaVaultV1`.
Its subscription ID is the fixed, content-free `TaisaVaultV1Changes`.
The record type is `TaisaEncryptedChangeV1`. A record name is a random,
canonical mutation UUID; it is never a title, message, entity name, or
recoverable user identifier. The only application fields are:

| Field | CloudKit type | Meaning |
|---|---|---|
| `vaultID` | String | Opaque vault UUID |
| `entityType` | String | Fixed allowlisted entity category |
| `schemaVersion` | Int64 | Encrypted domain schema version |
| `envelopeVersion` | Int64 | Cryptographic envelope version |
| `tombstone` | Int64 | 0 or 1 deletion marker |
| `ciphertext` | Asset | AES-GCM combined bytes, including nonce and tag |

The opaque record UUID is not duplicated in a field because `recordID` is a
CloudKit-reserved field name. Causal ancestry, device identifiers, entity IDs,
names, messages, goals, evidence, memory, recovery material, and key material
remain inside authenticated ciphertext and are not searchable CloudKit fields.
Apple can still observe account association, operation times, record counts,
approximate sizes, and service-level device/network metadata.

`CKSyncEngine.State.Serialization` and fetched ciphertext waiting for local
application are stored only in the existing SQLCipher `sync_state.engine_state`
checkpoint. The coordinator's durable change token advances with authenticated
local application. Uploads are capped at 200 records per batch, below CloudKit's
250-record request ceiling. Zone deletion and expired tokens surface as typed
recovery states; they do not delete local data.

The development schema must be created and inspected against the actual
development container during signed-device QA. Production schema promotion
requires a separate Baah approval, a verified development schema, and a
recorded promotion result before production distribution.

The automatic iPhone–iPad sync acceptance criterion remains deferred until a
paid Apple Developer Program team can provision the required capabilities and
Baah separately approves live development-container verification. No schema was
created, promoted, or changed by the Personal device lane.
