# Focused App Memory Script

## Foundations

- Problem: inspect the real memory footprint of the app the user is currently interacting with, not just its root process.
- Goal: provide a zero-argument shell entrypoint that resolves the frontmost macOS app and prints a descendant-aware RSS summary.
- Non-goals: sampling over time, private-memory attribution, or grouping unrelated sibling processes that do not descend from the focused app PID.

## Functional Spec

- The script resolves the current frontmost app at execution time and requires no input parameters.
- It prints app identity, the root PID, the combined RSS for the root process plus all descendant processes, and a per-process breakdown sorted by RSS.
- When the script is launched from the focused app itself, it excludes its own transient inspector subprocess tree from the total so the report does not self-inflate.
- It fails fast with a readable error when the frontmost app or its process table entry cannot be resolved.

## Technical Spec

- Frontmost app resolution uses JXA with `NSWorkspace.sharedWorkspace.frontmostApplication` so the script can query AppKit directly instead of scraping UI state through `System Events`.
- Process collection reads a single `ps` snapshot, builds a parent-child index in `awk`, walks the full descendant tree from the frontmost PID, excludes the current script subtree when present, and sums `rss` values in KiB before formatting them for output.
