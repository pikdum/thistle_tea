# Transformation and Polymorph acceptance

Validated on 2026-09-24 with native build-5875 clients. Appearance projection was
tested at `16897ec7`; the regeneration follow-up was tested at `72260b83`.
This covers transformation behavior, not general vanilla parity.

## Implementation and reference

`Logic.Appearance` selects the active transform, with harmful transformations
ahead of positive disguises and newer applications first within each group.
Removing a holder reveals another transform, the active shapeshift, or the
native model. Display, object scale, collision dimensions, creature weapons,
and regeneration all use that selection. Native dimensions remain canonical
inputs, so repeated synchronization does not compound scale.

Loaders compile DBC model geometry and VMangos display overrides into model
data. Orb of Deception selects by original race and gender. Creature transforms
include template equipment; shapeshifts retain their form scales. Presence and
the mob owner publish the resulting dimensions to metadata.

Reference paths under `refs/vmangos/src/game/` include
`Spells/SpellAuras.cpp` transformation and shapeshift handling,
`Objects/Unit.cpp` model restoration and `IsPolymorphed`,
`Spells/SpellEntry.cpp` spell classification, and
`Objects/Player.cpp` / `Objects/Creature.cpp` health regeneration.

## Native appearance results

Debugdruid (guid 9, level 60, night elf female) used item 1973, Orb of Deception.
Debugbidder (guid 11, level 60 mage) observed the druid and cast Polymorph during
a duel. Setup and actions used native client commands, item use, buff
cancellation, shapeshift controls, and logout/login. Tidewave was read-only.

| Transition | Display | Object scale | Radius | Combat reach |
| --- | --- | --- | --- | --- |
| Native night elf | 56 | 1.0 | 0.306 | 1.5 |
| Orb of Deception | 10144 | 1.0 | 1.5 | 1.5 |
| Newer Flip Out disguise | 4617 | 1.0 | 1.5 | 1.5 |
| Incoming Polymorph | 856 | 1.0 | 1.0 | 1.0 |
| Cat revealed after cancelling Orb | 892 | 0.8 | 0.8 | 1.2 |
| Cat cancelled | 56 | 1.0 | 0.306 | 1.5 |

Owner state and metadata agreed at each sampled transition. Polymorph overrode
both positive disguises; its removal revealed Flip Out. Cancelling Flip Out
revealed Orb. Logout saved the Orb holder with remaining duration, and reconnect
restored the same model and dimensions. Casting Cat Form under Orb retained the
disguise; cancelling Orb revealed Cat with its 0.8 scale. Leaving Cat restored
the original dimensions. The observer's target portrait tracked the disguises;
the druid client showed its world model and form controls.

The armed Defias Thug, guid `17379390962661268572`, changed from display 5035
and weapon display 7487 to sheep 856 with no weapon. Rank-one Frostbolt broke
Polymorph and restored the original model, weapon, radius, and reach. Killing
the creature during another Polymorph cleared the aura and restored its native
appearance on death. Respawn returned it to full health with its sword and no
transform holders.

## Regeneration follow-up

The first creature run exposed missing Polymorph recovery: the creature stayed
at 50/71 while transformed and in combat. The fix makes wild creatures recover
one third of maximum health per five-second tick during Polymorph. Players and
player-controlled creatures recover one tenth at their normal regeneration
intervals. Creature regeneration flags still apply. Player fractions carry
between ticks; flat regeneration bonuses remain additive, while ordinary
spirit, sitting, food, and percentage bonuses do not amplify Polymorph recovery.

A fresh server produced a level-four Thug with 86 maximum health and native
display 5036. The native client's health history showed `86 -> 63 -> 86 -> 65`:
rank-one Frostbolt damage, Polymorph recovery, then damage breaking Polymorph.
The owner trace recorded:

| Elapsed | Health | Display | In combat | Transform |
| --- | --- | --- | --- | --- |
| 2 ms | 63/86 | 5036 | yes | none |
| 3620 ms | 63/86 | 856 | yes | Polymorph |
| 7842 ms | 86/86 | 856 | yes | Polymorph |
| 22515 ms | 65/86 | 5036 | yes | none |

Four later samples spanning six seconds remained at 65/86 in combat, proving
the recovery exception stopped when Polymorph broke. The sword was visible again.

For the player run, `.modify hp 400` supplied an injured druid before the mage
cast. At 429/2533 health, Polymorph applied. Subsequent two-second ticks reached
682, 936, 1189, 1442, 1696, and 1949. The first two occurred in combat. After the
transform ended, ordinary ticks added only 14–15 health. The druid's client
printed the same health sequence and displayed the sheep model and debuff.

## Teleport interruption follow-up

During regeneration setup, a native `.go` command issued during Frostbolt
cleared the authoritative cast but left the client's cast bar running.
`f00029bd` routes world-transition cancellation through `Casting.interrupt/2`
and drains its typed effects with an explicit owner context before teleporting.
Both nearby and cross-map paths now send interruption feedback.

On a fresh server, the client cast Frostbolt 10180 and teleported approximately
two seconds into preparation. The nearby teleport produced the native
`SPELLCAST_INTERRUPTED` event and a red Interrupted cast bar, which then cleared.
Arcane Intellect 10156 cast successfully afterward. Repeating across maps
cleared the cast before entering the loading screen, completed worldport, and
again allowed Arcane Intellect. The creature remained at 86/86 health.

The final client session was
`/home/pikdum/.cache/thistle-wow-playtest.N09MpB`, with `near-interrupted` and
`cross-map-ready` screenshots. Owner traces are
`/tmp/thistle-teleport-cast-near.json` and
`/tmp/thistle-teleport-cast-world.json`; the server log is
`/tmp/thistle-teleport-cast-server.log`. The WoW GPU counter increased from
4.81 to 8.20 billion nanoseconds. No relevant server errors appeared, and the
client and server were stopped after acceptance.

## Automated checks

The final implementation passed `mix test.all` with 5752 tests,
`mix compile --warnings-as-errors`, `mix credo --strict`,
`mix format --check-formatted`, and `git diff --check`.

Coverage includes transform priority and refresh ordering, geometry
recomputation, aura removal and expiry, equipment restoration, all sixteen Orb
race/gender mappings, all six mage Polymorph variants, player regeneration
fractions and modifiers, controlled-creature rates, creature regeneration
flags, dead/ghost exclusions, and interruption packets for both teleport paths.
DBC and VMangos tests remain separately tagged.

## Evidence

- Appearance sessions: `/home/pikdum/.cache/thistle-wow-playtest.ZGNhba`
  (druid) and `/home/pikdum/.cache/thistle-wow-playtest.Wn9OFY` (mage).
- Appearance screenshots include `orb-active`, `overlapping-disguises`,
  `polymorph-active`, `reconnected-orb`, `orb-over-cat`, `cat-restored`,
  `native-restored`, and the mage's `creature-before`, `creature-polymorphed`,
  and `creature-restored`.
- Appearance traces: `/tmp/thistle-appearance-orb.json`,
  `/tmp/thistle-appearance-polymorph.json`,
  `/tmp/thistle-appearance-shapeshift.json`,
  `/tmp/thistle-appearance-native-restored.json`, and
  `/tmp/thistle-appearance-creature.json`.
- Regeneration sessions: `/home/pikdum/.cache/thistle-wow-playtest.ZdoyJF`
  (mage) and `/home/pikdum/.cache/thistle-wow-playtest.r81sno` (druid).
- Regeneration screenshots: `creature-healing`, `creature-after-break`,
  `player-healing`, and `player-healing-repeat` in those sessions.
- Regeneration traces: `/tmp/thistle-polymorph-creature-regen.json`,
  `/tmp/thistle-polymorph-creature-stopped.log`, and
  `/tmp/thistle-polymorph-player-regen.json`.
- Server logs: `/tmp/thistle-appearance-server.log` and
  `/tmp/thistle-polymorph-server.log`.

WoW's own DRM counters increased in every client process, confirming AMD
hardware rendering. The appearance and regeneration runs reported no relevant
server errors, failed spell validation, or unsupported commands. The clients
and servers were stopped through their retained session ownership paths.
