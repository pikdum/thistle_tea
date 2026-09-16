# Fade and temporary threat

Priest Fade now changes threat on enemies already tracking the priest.
The aura's amount and duration come from spell data: rank 5 (10941) at
level 50 subtracts 620 threat for 10 seconds. New enemies acquired while
Fade is active do not inherit the reduction, matching VMangos.

`Logic.Threat.set_temporary/3` stores the modifier on each mob's existing
threat reference. Threat earned during Fade is retained. Aura transitions
emit typed effects to those mob owners; the owners verify their incarnation
and wake their AI for normal victim selection. Expiry, cancellation, dispel,
and removal restore the modifier. Removing a threat reference, leaving
combat, or respawning discards its restoration state.

The implementation follows the pinned VMangos behavior, including its
zero floor: subtracting 620 from 324 produces zero, and removing Fade adds
the full 620 back. It does not restore a snapshot of the original value.

References:

- `refs/vmangos/src/game/Spells/SpellAuras.cpp`: `HandleAuraModTotalThreat`.
- `refs/vmangos/src/game/Threat/HostileRefManager.cpp`: `addTempThreat`.
- `refs/vmangos/src/game/Threat/ThreatManager.h`: temporary modifier storage
  and restoration.
- `refs/vmangos/src/game/Threat/ThreatManager.cpp`: `HostileReference::addThreat`
  and its zero floor.

## Real-client acceptance

Tested with two isolated build-5875 clients, Debugpriest and Debugwarrior,
on Programmer Isle. Both used the existing `.tgm` command to survive;
threat and spells were driven entirely through normal client actions.
Tidewave inspection was read-only.

1. Wait for `Debug seed ready`, then log in both characters.
2. Move the warrior to `.go xyz 16260 16338 69.44 451` and the priest to
   `.go xyz 16265 16338 69.44 451`.
3. Select a living Skeletal Flayer with Tab. Start the warrior's attack
   with `/script AttackTarget()`, assist from the priest with
   `/assist Debugwarrior`, then press Escape on the warrior to stop attacking.
4. Cast Smite from the priest. Wait for the mob to target the priest.
5. Cast Fade and observe the mob's target-of-target change to Debugwarrior.
   After 10 seconds, observe it return to Debugpriest.

The final run used mob GUID 17379390991937510293. One-second owner samples
recorded the following; times are relative to sampler startup:

| Seconds | Victim | Priest threat | Warrior threat | Temporary modifier |
| --- | --- | --- | --- | --- |
| 0–9 | Debugpriest | 324 | 44.8 | None |
| 10–19 | Debugwarrior | 0 | 44.8 | −620 |
| 20–30 | Debugpriest | 620 | 44.8 | None |

Screenshots confirmed the Fade buff/countdown and both target changes.
The server recorded `CMSG_CAST_SPELL: Fade - 10941`. No gameplay owner or
temporary-threat errors occurred during the accepted run. Initial login
attempts before debug seeding completed produced an existing auth failure;
retrying after startup succeeded. The second client initially selected the
already-online rogue and was rejected until a different character was
chosen. Unimplemented login/query warnings were also present.

An initial attempt was discarded because `/script StopAttack()` does not
exist in this client and the warrior kept attacking. Use Escape, and avoid
selecting a dead corpse with `/target Skeletal` when repeating the check.

Retained evidence:

- `/home/pikdum/.cache/thistle-wow-playtest.MaKLsS/screenshots/current.png`
- `/home/pikdum/.cache/thistle-wow-playtest.MaKLsS/screenshots/switched-to-warrior.png`
- `/home/pikdum/.cache/thistle-wow-playtest.MaKLsS/screenshots/returned-to-priest.png`
- `/home/pikdum/.cache/thistle-wow-playtest.gG96ax/`
- `/tmp/thistle-fade-switch.txt`
- `/tmp/thistle-fade-server.log`

Automated coverage checks threat accumulation, clamping, refresh/replacement,
target reselection, reference cleanup, aura expiry and removal causes,
effect delivery, stale incarnation rejection, and the real DBC definition.
Removal causes and combat cleanup were tested automatically; the client
check exercised natural expiry.

Final validation: `mix compile --warnings-as-errors`, `mix test.all`
(2,785 passing tests), `mix credo --strict`, formatting, and diff checks.
Both isolated clients and the local server were stopped; evidence was retained.
