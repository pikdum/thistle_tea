# Vanilla global cooldowns

Implementation: `dc6e814c`. Vanilla haste correction: `84165ff7`.

Global cooldowns now retain the spell's DBC start-recovery category. Spells share
that category's deadline even when their own start-recovery time is zero. This
matters for spells such as Bestial Wrath: it observes an existing category-133
cooldown without starting another one. Other recovery categories stay independent.

Spell-modifier operation 21 adjusts player global cooldown duration through the
existing family-mask selection. Flat and percentage changes are applied before
truncating milliseconds and clamping at zero. A running deadline retains the
duration captured when the cast began. Charged modifiers survive cancellation and
are consumed through the existing successful-cast lifecycle.

Cancelling or interrupting preparation clears that cast's recovery category.
Completed instant spells and active channels retain their cooldowns. Triggered
casts neither start a global cooldown nor clear an unrelated running one. These
rules remain in `Spell.Cooldowns` and the shared `Logic.Casting` cancellation path.

## Reference and version correction

Category lookup and cancellation were checked against VMangos's
`SpellCaster::AddGCD`, `HasGCD`, and `ResetGCD`, and `Spell::cancel`. Operation 21
was checked against `Player::AddGCD` and the DBC item-set bonuses.

VMangos also applies ordinary spell haste to global cooldowns. Native build-5875
testing contradicted that behavior: Mind Quickening shortened Flash Heal's cast
to 1,127 ms, while the client reported a 1.5-second global cooldown. Blizzard's
[patch 2.4 notes, reproduced by Wowhead](https://www.wowhead.com/patchnotes=2.4.0),
identify haste-based global cooldown reduction as a change in that later release.

The final implementation therefore preserves vanilla's unchanged global cooldown
under ordinary haste and slow effects. Explicit operation-21 bonuses still work:
Prophecy reduces Flash Heal to 1,400 ms and the Immolate bonus reduces its global
cooldown to 1,300 ms. This is an intentional difference from the current VMangos
haste calculation. Its map-update compensation is also unnecessary for this
server's immediate packet dispatch.

## Automated verification

- `mix test.all`: **5,531 passed**.
- `mix compile --warnings-as-errors`, `mix credo --strict`: passed.
- Formatting, whitespace checks, and commit hooks: passed.

Tests cover category isolation, zero-duration category members, exact deadlines,
modifier family/mask selection, flat/percentage ordering, zero clamping,
nonplayer behavior, modifier expiry, cancelled versus completed casts, preparing
versus active channels, triggered casts, charge consumption, and actual cast
validation. DBC tests check Prophecy, the Immolate bonus, Mind Quickening, Sinister
Strike, and Bestial Wrath. Modifier application and removal also produce the
expected client operation-21 updates.

## Native build-5875 acceptance

The final fresh server used Debugpriest (GUID 4), raised to level 60 through
existing development commands. God mode remained disabled. The character targeted
herself, and `.modify hp` supplied missing health for actual heals. Mind Quickening
and Prophecy's passive were learned with `.learn`; this verifies the spell-modifier
path rather than acquisition of the corresponding equipment.

Read-only Tidewave samplers ran before the client actions and inspected the player
owner every 20 ms, retaining only changes. Native key input drove cancellation and
paired casts. Lua callbacks only observed the client cooldown display in accepted
timing runs; callback-driven attempts to cast were not treated as input evidence.

| Check | Client and authoritative result |
| --- | --- |
| Ordinary Flash Heal | Cast and global cooldown both 1,500 ms |
| Cancel during preparation | Cast and recovery deadline both cleared |
| Retry after cancellation | Replacement accepted 1,017 ms after the original start, before its old deadline |
| Mind Quickening | Cast 1,127 ms; server global cooldown 1,500 ms; client `GetSpellCooldown` reports 1.5 |
| Hasted repeat | Next accepted cast started after 1,617 ms and completed another heal |
| Prophecy Flash Heal bonus | Cast and global cooldown both 1,400 ms; client reports 1.4 |
| Prophecy repeat | Second cast accepted after 1,434 ms, before an unmodified cooldown would expire |

The accepted Prophecy pair used Flash Heal rank 6 (10916). Its start timestamps
were `-576460341764` and `-576460340330`. The first heal changed health from 138 to
884; the second changed 922 to 1,606, with ordinary regeneration between them.
Both charged the expected mana cost. Screenshots show the cooldown value, cast
bar, and healing feedback. The cancellation run also used rank 6; the first hasted
cast used rank 7 (10917), followed by rank 6.

Final inspection found no active cast or blocking global cooldown, ordinary cast
speed restored to 1.0 after Mind Quickening expired, and the retained Prophecy
passive still producing a 1,400-ms duration. No server errors or validation
failures occurred. Existing unsupported account-data, GM-ticket, and meeting-stone
warnings appeared at login.

## Evidence and cleanup

Final session: `/home/pikdum/.cache/thistle-wow-playtest.6t8omL`.
WoW's own DRM counters confirmed AMD GPU rendering. The helper-owned session and
retained server were stopped after acceptance.

Useful screenshots under `screenshots/`:

- `gcd-cancel-keys.png`
- `gcd-haste-fixed.png`
- `gcd-prophecy-pair.png`
- `gcd-prophecy-early-heals.png`

Retained evidence:

- `/tmp/thistle-global-cooldown-final-server.log`
- `/tmp/thistle-global-cooldown-final-tests.log`
- `/tmp/thistle-gcd-final-cancel-keys.txt`
- `/tmp/thistle-gcd-final-haste.txt`
- `/tmp/thistle-gcd-final-prophecy-early.txt`
- `/tmp/thistle-gcd-final-state.txt`
- `/tmp/thistle-gcd-sample.exs`
- `/tmp/thistle-global-cooldown-final-gpu.txt`

The earlier stopped session `stF8U1` and its server log
`/tmp/thistle-global-cooldown-server.log` retain the client evidence that exposed
the haste mismatch. Final acceptance used the fresh server above.
