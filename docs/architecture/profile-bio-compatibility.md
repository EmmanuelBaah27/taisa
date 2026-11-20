# Profile Bio compatibility

The profile UI and active Product contracts expose Display name and Bio. Bio uses
the existing encrypted `biography` field. The active query, draft, validation,
Preview fixture, and command API do not expose `headline`.

The encrypted database and archive contracts retain `headline` for backward
compatibility. Existing values remain stored but inactive. Opening or editing You
does not copy, display, validate, overwrite, or delete them. New active profile
records store an empty compatibility value. No schema version or archive shape
changes.

Regression tests prove that an old stored headline does not populate Bio. The
tests also prove that active profile edits preserve the stored compatibility
value. Empty first-build stores do not create a profile merely because You opens.

## Auto-save editor

The approved editor exposes Display name and Bio with a 500ms typing-pause
save. Writes are serialized in YouModel, and edits received during an earlier
write are drained before close reports success. A finished older write does not
replace the current draft. The explicit close control waits for all latest edits;
failure keeps the editor and text available with a retry action. An unchanged
editor closes without creating an empty profile. Scene inactivity requests a
flush, but does not promise that an OS termination will preserve an uncommitted
in-memory draft. No profile browsing or editing initiates AI/network requests.

Display name and Bio use the same `ProfileInputValidator` as encrypted storage
and Preview. Validation identifies the affected field before persistence. Bio
accepts line breaks and rejects other control characters. An invalid draft can
close without being discarded and reappears when the editor reopens. Retry is
reserved for persistence failures that can succeed without changing the draft.
