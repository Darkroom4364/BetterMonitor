# Roadmap

## #1 — display modes

Proposed bounded slice, awaiting review and merge: per-display named favorites save, list, apply,
and delete only exact offered desktop modes, with up to five canonical names per display. This does
not add custom resolutions, unlock HiDPI modes, or complete #1's broader display-mode work.

Favorites are available only when a complete, non-sentinel vendor/model/serial identity is available.
Displays without one report stable identity unavailable and do not persist or apply a favorite, avoiding
cross-display collisions from transient display IDs or names.
