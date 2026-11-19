# Profile Bio compatibility

The profile UI exposes Display name and Bio. Bio uses the existing encrypted
`biography` field; `headline` remains an internal historical schema field.

When the local You client loads an existing profile with blank biography and a
nonblank headline, it moves the headline into biography using the normal
ProfileCommandRepository mutation path. The source headline is cleared after
being copied so intentionally clearing Bio later cannot resurrect it. Existing
nonblank biography is never overwritten. A conflicting historical headline is
retained until the user edits the visible profile, then retired so it cannot
later repopulate a cleared Bio. Empty first-build stores do not create a profile
merely because You opens. No schema version or archive shape changes.

The compatibility write participates in the existing encrypted mutation and
recovery mechanisms. Failure follows the existing content-free You load error
path and must not be reported as a successful move. Regression cases cover a
legacy headline, repeated loads, deliberate Bio clearing, an existing biography,
and an empty store.

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
