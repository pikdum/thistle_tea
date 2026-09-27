# Mechanical repairs

Mechanical healing is implemented by `5958fa0f`; the dragonling correction
is `37d91cc6`. Spell effect 75 now uses
the shared healing amount calculation and ordinary health transition, with
caster and recipient bonuses, effect immunity, and overheal clamping. Its
combat feedback is noncritical and does not request healing hit procs or
assist threat. The existing target validator enforces the spell's friendly,
living, mechanical recipient requirement.

Reference: local VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`,
`SpellEffects.cpp::EffectHealMechanical` and `SpellCaster.cpp::DealHeal`.
Item 11590, Mechanical Repair Kit, uses spell 15057, Mechanical Patch Kit:
700 base healing, a two-second cast, a ten-yard range, Engineering 200,
one consumed charge, and a two-minute cooldown.

## Dragonling follow-up

The first native attempt exposed dragonlings spawning with one health.
Their VMangos templates have a health multiplier of 0.000001 and no addon
auras. The loaded templates therefore produce zero base health, clamped to
one. Tracing confirmed that the item wrapper, triggered summon, and owner
registration all completed successfully.

The guardian loader now applies the matching DBC creation passives before
publication: Mechanical Dragonling 23051, Mithril Mechanical Dragonling
23050, and Arcanite Dragonling 23052. These spell records supply 300, 500,
and 700 health and 50, 90, and 115 flat damage respectively. This association
is a local correction based on the matching DBC spells; it was not present
in the inspected VMangos summon path or seed aura links. The existing aura
logic derives the bonuses, and the newly created guardian starts with full
resources. Ordinary guardian scaling and templates remain unchanged.

## Automated verification

`mix test.all` passed all **7,081 tests**. Compilation with warnings as errors,
strict Credo, formatting, and whitespace checks passed. No dependency
allowlist changed.

Coverage includes mechanical-only target validation, modifiers, noncritical
feedback, absence of healing hit procs and assist threat, immunity and its
removal, dead recipients, overhealing, actual DBC repair amounts, passive
health/damage, full starting health, repeated recomputation, and item identity
through the trinket trigger chain. The DBC wrapper test isolates VMangos
overrides and spell caches so it also passes in the complete tagged suite.

Gate logs: `/tmp/thistle-mechanical-final-{all,compile,credo}.log`.

## Native acceptance

An isolated GPU build-5875 client used Debugwarrior, GUID 1, level 60 and
Engineering 300. Native GM commands granted the items; normal inventory
equipment, binding confirmation, trinket activation, and item targeting drove
the gameplay. Tidewave inspected state without replacing gameplay mutations.

Arcanite Dragonling spawned at 700/700 with passive 23052 and fought the
seed Skeletal Flayers. Mithril Dragonling spawned at 500/500 with passive
23050. Right-clicking the repair kit and clicking the friendly target frame
produced the native cast bar and the chat message reporting a 713-point
repair. The caster's inspected healing bonus was 13. Kit count changed from
five to four, and the cooldown's ready/start difference was 120,000 ms.

Both completed guardians subsequently disappeared from their owner's
guardian map, entity registry, world position, and metadata.

A second repair used Mechanical Dragonling. A sampler started before item
activation recorded 300/300 on spawn, damage to 178/300, then a return to
300/300 at the repair's completion. At that same transition, kit count fell
from four to three and cooldown 15057 appeared. The client displayed another
713-point heal; the authoritative health increase was correctly capped at
122. Further combat killed the guardian, and its owner map cleared after the
corpse delay. These samples are in
`/tmp/thistle-mechanical-repair-final.log`; `mechanical-repaired.png` shows the
healed target and remaining three kits.

Logout and reconnect retained all three kits and the same cooldown, with
30,613 ms remaining when sampled, and restored no departed guardians.
`/tmp/thistle-mechanical-logged-out.log` also confirms that the final guardian
had left the registry, world position, and metadata. Reconnect evidence is
`/tmp/thistle-mechanical-reconnected.log` and `repair-reconnected.png`.

The early Lua item-use attempts opened client targeting without sending a
repair request. They are not counted as successful casts or server-side
invalid-target acceptance. The successful cast used explicit mouse targeting.

Artifacts are retained under
`/home/pikdum/.cache/thistle-wow-playtest.ewUOp6/screenshots/`, including
`repair-during.png`, `mithril-repair.png`, `kit-manual.png`, and
`kit-healed.png`. Server log: `/tmp/thistle-mechanical-server3.log`.
Authoritative logs: `/tmp/thistle-mechanical-repair-{accepted,second}.log`,
`/tmp/thistle-mechanical-manual-heal.log`,
`/tmp/thistle-mechanical-bonus.log`, and
`/tmp/thistle-mechanical-guardian-cleanup.log`.

WoW process 2306425 had `amdgpu` DRM graphics counters increasing from
25,034,458,053 to 37,539,432,446 ns. Evidence:
`/tmp/thistle-mechanical-gpu2-{before,after}.log`.

The server log had no owner, casting, visibility, or network failures. Its
unimplemented account-data and GM-ticket warnings were unrelated login
traffic.

The helper-owned client service and retained server were stopped after
acceptance. Logs and screenshots remain available. No push was performed.
