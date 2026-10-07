# Native encrypted storage dependencies

The native `TaisaStorage` module uses the SQLCipher-managed GRDB fork at the exact
`7.11.1` tag (`https://github.com/sqlcipher/GRDB.swift.git`). The committed
`apple/Packages/TaisaFoundation/Package.resolved` locks that source revision to
`a285e4ca87ec6b3584c97b0ec25fc61fec02de60` and its SQLCipher.swift binary
package to `4.19.0` (`39f212458aeb88e33bdac2200a793a3f0d55d32b`).
SQLCipher.swift `4.19.0` packages SQLCipher core `4.19.0`. SQLCipher 5 beta is
outside this approved graph. The project links only the managed fork’s `GRDB`
product through `TaisaStorage`; it does not add a second SQLite product.

The runtime probe requires 32 bytes of key material, supplies them to SQLCipher
before reading the schema, checks `cipher_version` and `cipher_integrity_check`,
enables foreign keys and WAL, and fails closed for a missing file or unreadable
encrypted database. Its integration test reopens an encrypted file, rejects a
wrong key, and checks the database bytes for a private canary. This is a stack
proof, not the production key lifecycle, schema, or sync implementation.

GRDB is MIT licensed (copyright 2015–2025 Gwendal Roué). SQLCipher Community
Edition and its Swift package carry the three-clause BSD notice (copyright
2025 Zetetic LLC); their binary redistribution notice must accompany shipped
builds. SQLite portions are public domain. The upstream notices are in the
resolved GRDB `LICENSE` and SQLCipher.swift `LICENSE.md` package checkouts.

The iOS 26 preferred Passwords-manager save API requires a Web Credentials
associated domain. The installed Xcode 26.1 SDK does not declare
`ASCredentialDataManager` or `ASAutoFillURLScope`, so the future save adapter
is behind `TAISA_HAS_CREDENTIAL_DATA_MANAGER_SDK` as well as iOS availability.
Task 4 must validate a supporting SDK before enabling that condition. The
iOS 17–25 path requires explicit manual saving and confirmation. This task
compile-checks the available Apple frameworks; capability
creation and real CloudKit use remain gated later in the approved plan.

Development, preview, and production retain their separate bundle identities
(`com.taisa.app.dev`, `com.taisa.app.preview`, `com.taisa.app`). Task 7 now declares
the approved development and production CloudKit entitlements in local project
configuration; Preview remains fake-only. External Apple capability state is
unverified, and no production CloudKit schema has been promoted. See
[`cloudkit-schema.md`](cloudkit-schema.md) for the exact local schema proposal.
