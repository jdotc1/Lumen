# A single-window batch utility

A batch-processing app can use Lumen’s foundation and window scaffold without adopting a
multi-pane workspace. Keep processing, file access, persistence and retry policy in the app.
Lumen supplies the visual roles and components that present those operations.

## Window and state

Build the primary window with `LumenUtilityWindow`: a compact top bar, an input queue, processing
status and a clear result area. Set a minimum window size appropriate to the queue’s columns and
actions. Use neutral sample images when demonstrating the workflow.

Represent the workflow explicitly: empty, ready, working, completed, partially completed and
failed. The empty state offers one primary input action. The ready state summarizes the queue
and destination. While working, show completed and total item counts and a cancel action when
the processor supports cancellation. Keep item-level failures visible after partial success.

## Queue, output and retry

Show each item’s name, size and processing state. Keep detailed diagnostics available without
crowding the queue. Preserve original inputs and make the output destination clear before work
starts. The app decides how to resolve filename collisions and whether a retry processes failed
items only. Present that scope in the retry action’s label or explanation.

## Themes and settings

Use shared roles for backgrounds, labels, status colors and actions. Define a domain pack only
for meanings absent from Lumen’s shared packs. Keep theme identifiers and saved user overrides
stable during adoption. Put persistent processing options in Settings; keep options needed for
the current batch close to the queue.

## Adoption and acceptance

Pin an exact released Lumen commit and read CHANGELOG before moving it. Introduce the foundation,
then the scaffold, then remove redundant adapters. Check the changed queue and result states at
the window minimum, long filenames, partial success and retry. Record app-owned processing tests
separately from Lumen layout or theme checks. Reuse valid evidence for unchanged inputs and
follow [client versioning](clients.md) for future pin changes.
