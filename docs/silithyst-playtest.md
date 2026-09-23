# Silithyst resource objectives

The resource loop uses the existing quest-object admission, aura transitions,
spell effects, reputation, honor, and quest-credit systems. `ResourceRace` keeps
team counts and the last controlling faction pure; `World.System.OutdoorPvp`
serializes contributions and monitors participating player owners. Progress is
runtime-only and resets with the server.

Picking up geyser 181598 or mound 181597 applies Silithyst 29519 and the matching
faction aura, flags contested PvP, and prevents consuming a second resource.
Aura 191 caps run and swim bonuses before snares. Carrier removal also removes
the faction aura; delayed applications cannot restore an orphan faction aura.
Cancellation, death, and interrupted carriers leave a wild mound for 180 seconds.
Accepted delivery consumes the aura without dropping a mound.

Alliance trigger 4162 and Horde trigger 4168 require a living carrier on map 1,
the corresponding faction, and the existing authoritative trigger-range check.
A turn-in awards quest credit, Traces of Silithyst, 199 honor, and two 10-point
Cenarion reputation rewards through the reference spell chain. The legacy
effect 122 on spell 31247 is normalized to the existing reputation effect.
Reaching 200 resets both counters and changes control. The controlling faction
receives Cenarion Favor in Silithus and both Ahn'Qiraj zones; exit removes it.

Milestone NPC announcements and decorative dust-bag staging are separate content
work. This acceptance covers the resource mechanics, not complete Silithus event
presentation. Threshold capture, opposing faction rejection, control replacement,
and Ahn'Qiraj eligibility are automated checks; no native 200-delivery or raid-buff
acceptance is claimed here.

## Native acceptance

Build 5875, human Debugmage raised to level 60 through the existing developer
command. Both isolated sessions used the RX 7900 XT; WoW's own `amdgpu` fdinfo
reported nonzero graphics work.

- Initial session: `/home/pikdum/.cache/thistle-wow-playtest.k2fvlL`.
- Corrected reward session: `/home/pikdum/.cache/thistle-wow-playtest.Eq8jU5`.
- Server logs: `/tmp/thistle-silithyst-server.log` and
  `/tmp/thistle-silithyst-final-server.log`.

The native client opened DB geyser 49339 near `-7478.8, 1447.77, 6.12544` using
Opening 6247. The owner retained carrier 29519, faction aura 29894, and contested
PvP. The client showed the glowing carrier and faction counters at 0/200.

At `-7160, 1397.92`, cancelling helpful buffs through the client removed both
carrier auras and created one unowned mound. Right-clicking that mound recovered
the resource and consumed the mound. The first native delivery exposed the
unsupported reputation effect; the final session repeated delivery after the
loader correction.

From `-7149, 1397.92, 5`, walking toward the Alliance collection structure crossed
the actual area trigger. Final owner evidence showed Alliance 1, Horde 0, quest
9419 complete with one objective credit, Traces 29534, no carrier/faction aura,
199 honor, and Cenarion reputation increased from 0 to 22. The human racial bonus
accounts for the extra two reputation points. `reward-verified.png` records the
client quest objective, buff, and updated counter.

With the second real geyser near `-6849.17, 1282.89`, Sprint produced 10.5 yards/sec
without the carrier. Resetting Sprint with the existing Preparation spell and
casting it while carrying retained both Sprint and Silithyst at 7 yards/sec.
The capped state is recorded in `sprint-capped.png`.

After returning outside the collection trigger, disabling god mode and using
`.die` produced health 0, removed both carrier auras, and created exactly one
mound at the death position. `death-drop.png` records the corpse and mound.
Release Spirit, the normal corpse reclaim button, and a right-click on the mound
restored a living carrier. While a ghost, developer chat used a whisper to self
because the client does not send ordinary say messages while dead.

Logging out while carrying created one new mound, stopped the player owner, and
saved neither carrier aura in `CharacterStore`. Re-entering the world restored
1/200 progress and no carrier. Recovering that mound and changing to map 451
removed the carrier, left one mound at the old Silithus position, removed the
world-state display, and left zero outdoor objective subscribers. These stages
are recorded in `logged-out.png`, `reconnected.png`, and `left-silithus.png`.

The final server log contained no error, unsupported-command, unhandled-message,
or failure entries. Both helper-owned client services and both retained server
processes were stopped before the final full test run.

## Final validation

- `mix test.all`: 5,176 passed, seed 848891.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: no issues.
- `mix format --check-formatted` and `git diff --check`: passed.
