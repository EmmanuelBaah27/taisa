# Profile Bio compatibility

The profile UI exposes Display name and Bio. Bio uses the existing encrypted
`biography` field; `headline` remains an internal historical schema field.

When the local You client loads an existing profile with blank biography and a
nonblank headline, it moves the headline into biography using the normal
ProfileCommandRepository mutation path. The source headline is cleared after
being copied so intentionally clearing Bio later cannot resurrect it. Existing
nonblank biography is never overwritten; a conflicting historical headline is
retained internally. Empty first-build stores do not create a profile merely
because You opens. No schema version or archive shape changes.

The compatibility write participates in the existing encrypted mutation and
recovery mechanisms. Failure follows the existing content-free You load error
path and must not be reported as a successful move. Regression cases cover a
legacy headline, repeated loads, deliberate Bio clearing, an existing biography,
and an empty store.
