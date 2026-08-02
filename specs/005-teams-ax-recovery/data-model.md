# Data Model: 005-teams-ax-recovery

No persistent data, configuration schema, or entities are introduced or
changed by this feature. The recovery parameters (two wake-flag attribute
names, 12 attempts, 150 ms interval, 2.0 s messaging timeout) are compile-time
constants in `Sources/Overtype/Support/AXHelpers.swift`, bound to the
empirically validated values recorded in [research.md](research.md).

Runtime-only value:

- **Recovery attempt state** (function-local): the optional fallback candidate
  element remembered while retrying (an element that was found but does not
  yet expose a non-empty selection). It never outlives one
  `getFocusedElement` call.
