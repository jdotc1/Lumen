# Theme reports from the command line

The `lumen-theme` executable uses Lumen's core registry without launching an app.
Existing `validate <file.json>...` and `export <directory>` output is unchanged.

```sh
lumen-theme diff <a> <b> [--format text|markdown|json]
lumen-theme contrast <theme> [--format text|markdown|json]
```

Each input accepts a theme file, a built-in ID (for example `lumen.standard` or
`lumen.midnight`), or the JSON array written as `builtin-themes.json` by `export`.
Files are decoded and inheritance is flattened. Parents in the same export take
precedence over built-ins. Duplicate IDs, unsupported schemas, malformed files,
unresolved inheritance and unreadable files are input errors.

Two single themes compare directly, even if their IDs differ. When either input is
an export array, themes match by ID over the union of both inputs. Empty exports
are valid. Added and removed themes are identified explicitly.

`diff` emits no text or Markdown for identical inputs; JSON emits an empty array.
Colors use canonical hex and report `old → new`, with `absent` for added or removed
palette keys. Each supported appearance (including declared Increase Contrast
variants) is separate. The report compares flattened palette declarations and
resolved registered colors, so fallback changes are visible too. Metrics and
nested depth leaves report inherited declarations; absent values retain app defaults.
Color-space and high-contrast mode changes are also reported. Names and summaries
are descriptive metadata, not theme values, and are not diffed.

Affected contrast rows include every requirement whose foreground or ground changed,
plus requirements whose ratio changed indirectly through a fallback or backdrop.
Ratios use the validator's shared computation: foreground compositing, the worst
possible translucent backdrop, theme color space, and raised-ground substitutions.
The report includes registered token requirements, pack contrast pairs, and visibility
rules with contrast thresholds. Distance-only, lift and opacity checks remain in
`validate`; PASS/FAIL here describes the contrast threshold only. Raised contexts
are included even when their colors equal the normal context, except where an
explicit raised-role requirement already covers the pair.

`contrast` reports every contrast requirement with ratio and minimum, failures
first within each theme, then appearance and rule ID. Display ratios round to two
decimal places; pass/fail uses the unrounded value. JSON preserves numeric precision.
Both commands exit 0 for a successfully read report, even with differences or
failing pairs; input/argument errors exit nonzero. Use `validate` for a validation gate.

JSON is an array of theme objects with `theme`, `status`, `changes`, and `contrast`.
Changes contain `appearance`, `kind` (`added`, `removed`, `changed`), `path`, and
optional string `before`/`after` values. Contrast rows contain `appearance`, `rule`,
`foreground`, `ground`, `context`, and optional `before`/`after` objects, each with
numeric `ratio`, numeric `minimum`, and boolean `passes`. Missing sides are omitted.
Rule IDs identify registry positions within this executable; they are not stable
identifiers across registry revisions. Output order is deterministic.

## Release review

`Scripts/release.sh` runs the API check and the strict build, then this step, then the full
tests, so a stop never costs a full run. It exports the current registry with the built
executable and reads `Docs/reference/builtin-themes.json` from the previous tag using `git show`.
It calls `Scripts/release-theme-values.py <cli> <previous> <current> <changelog> <version>`.
The helper invokes `diff --format markdown`; an empty report leaves the changelog
unchanged and continues.

A nonempty report creates or updates `### Visual` → `#### Theme values` in the
requested version section. Generated markers allow replacement without duplicating
the heading or deleting authored notes. When that edits the changelog, the helper exits 3 and
release.sh stops before **any tag or push**. Review the report, commit the changelog, and run
release.sh again: a committed changelog that already carries the exact report continues to the
tests and the tag. release.sh refuses to start with uncommitted changes, so an unreviewed report
can't be released.
Missing previous exports and report errors stop the release rather than skipping review.

The helper can be tested against fixture exports and a scratch changelog without
running release.sh: `python3 Scripts/test-release-theme-values.py .build/debug/lumen-theme`.
DTCG/CSS import/export formats and `pack validate` remain separate future commands.
