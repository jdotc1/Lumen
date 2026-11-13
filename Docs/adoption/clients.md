# Apps that use Lumen

Lumen leads its own design-system plans. Apps consume its releases and decide when to adopt
them; Lumen never waits for a client’s migration, pin update or release.

## Pin exact commits

Use an exact, reviewed commit in the app’s package resolution. Record the corresponding Lumen
version and the app’s domain-pack compatibility notes. Keep domain-specific roles, persistence,
backend operations and release decisions in the app’s repository.

## Read changes before upgrading

Read every intervening CHANGELOG entry, especially breaking API changes, renamed roles,
theme-schema changes and platform requirements. Plan any data migration or adapter removal in
the app. The [migration guide](migrating-a-design-system.md) describes a phased approach; the
[batch utility guide](batch-utility.md) illustrates a single-window workflow.

## Report shared gaps

Describe the user-visible behavior, expected result and smallest public-API reproduction. Include
the exact Lumen commit, platform version, relevant window size, theme and appearance. Keep private
app source and user data out of reports. Separate reusable design-system gaps from app-owned
policy. Lumen evaluates reports against its plans and publishes reusable changes on its own schedule.

## Move pins after Lumen ships

Once a Lumen release supplies the required behavior, update the app’s exact pin, adapt its domain
pack and run checks for the changed boundary. Reuse valid receipts for unchanged inputs. Record
remaining app-specific work in the app’s own issue tracker. An app can remain on its previous pin
while it prepares adoption; that does not block Lumen’s next release.
