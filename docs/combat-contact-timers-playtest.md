# Combat contact timer acceptance

Gameplay commit: `92795e2c`, validated on 2026-09-27.

## Behavior and reference

Outgoing contact with an ordinary PvE creature no longer imposes a fresh
five-second combat hold. Contact with the opponent responsible for a longer
launch hold shortens it to the next one-second combat check. Shorter remaining
holds keep their expiry. Unrelated contacts preserve the longest hold and its
opponent. Actual threat references still retain combat.

Incoming contact against players and player-owned pets retains five seconds,
as does outgoing contact against a victim using the PvP timer. Classification
includes players, player-owned pets, player-charmed units, and creatures with
the no-threat-list flag. Controlled-creature contact still gives its player
owner an explicit five-second hold. Merely enabling auto-attack no longer
starts or refreshes player combat. An interrupt-regeneration aura retains
existing combat after its timer expires.

The pure `CombatTimer` owns timer selection, opponent tracking, expiry, and
cleanup. Contact effects carry the victim's timer classification through
delivery, including lethal hits. Player and pet transitions keep their existing
owners and publication paths. Spell contact owns spell combat entry; ordinary
white swings enter through resolved attack feedback. No dependency-ratchet
allowances were added.

Reference: local VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`,
`Unit::SetInCombatState`, `SetInCombatWithVictim`,
`SetInCombatWithAggressor`, `UsesPvPCombatTimer`, `Attack`, and the combat-timer
update in `Unit.cpp`. This implements the contact rules following the
[launch-combat work](spell-launch-combat-playtest.md). Ordinary NPC threat and
evade behavior continue through the existing engagement lifecycle; this is not
a replacement of all no-threat-list NPC AI behavior.

## Native opening kill and respawn

The genuine build-5875 client ran committed code without source edits or live
recompilation. Session: `/home/pikdum/.cache/thistle-wow-playtest.vdT3VA`.
Debugmage, GUID `5`, level 50, cast Fireball rank 9 (`10149`) against Defias
Cutpurse `17379390963600795669` on map 451. The mage stood about 30 yards away
at `{16687.2, 16268.1, 69.44}` with god mode enabled. Actions came from the
client; Tidewave only observed state.

`/tmp/thistle-contact-timers-opening-kill.log` records:

| Sample time | Observed transition |
| --- | --- |
| 3 ms | Both units peaceful; victim health 120, no threat or player references. |
| 2,813 ms | Fireball preparation begins; caster remains peaceful. |
| 6,330 ms | Launch enters caster combat, flags `561160` in state and metadata, with a 1,749 ms hold naming the victim. The victim remains peaceful. |
| 7,602 ms | Lethal impact leaves victim health zero and empty threat. |
| 7,654 ms | Contact retains the remaining 473 ms window rather than adding five seconds. |
| 8,328 ms | Caster leaves combat, 726 ms after observed death. Flags return to `36872`; contact time and timer opponent clear. |
| 37,627 ms | Victim respawns at 120 health with incarnation `128`, replacing `64`. Threat remains empty and the caster stays peaceful. |

A client Lua observer detected caster combat while the victim was peaceful
and requested logout. The client rejected it with `You can't logout now.`
Screenshot `opening-kill.png` shows that rejection, 452 Fireball damage, and
the subsequent `combat=nil` diagnostic.

## Active threat without landed attacks

Using existing developer commands, the mage learned Charge Stun (`7922`)
and Battle Stance (`2457`). At 22 yards, Charge Stun supplied its explicit
five-second active-threat hold and enabled auto-attack. The attack intent
remained enabled throughout the test, with no landed swings or victim threat.

In `/tmp/thistle-contact-timers-active-threat.log`, caster combat begins at
2,890 ms and ends at 7,906 ms: 5,016 ms later. Auto-attack is still true after
combat clears. Both timer fields clear, state and metadata agree, and the
victim stays peaceful at 120 health throughout. `active-threat-start.png`
shows the rejected logout; `active-threat-expired.png` shows the armed pose,
ordinary out-of-range swing feedback, and the peaceful client diagnostic.

## Bloodrage aura hold

Debugwarrior, GUID `1`, level 50, cast learned Bloodrage (`2687`) from the
peaceful Programmer Isle spawn. Initial health was 2,729, rage zero, and rage
capacity 1,000. The warrior had no victim, attack intent, or threat references.

`/tmp/thistle-contact-timers-bloodrage.log` records combat and the
interrupt-regeneration aura at 3,319 ms, with health 2,514 and rage 100.
At 8,333 ms the five-second timer has expired, but the aura retains combat.
At 13,317 ms the aura and combat clear together, 9,998 ms after observed entry.
State and metadata return to flags `36872`; contact time is nil. Rage reaches
200, then decays while health regeneration resumes.

The client printed combat status once per second. Screenshots
`bloodrage-hold.png` and `bloodrage-expired.png` preserve combat through nine
seconds and `combat=nil` from ten seconds. The first screenshot was captured
after expiry; its chat history, together with the sampler, records the hold.
An initial read-only baseline probe referenced a nonexistent player name
field; the corrected probe is
`/tmp/thistle-contact-timers-warrior-baseline-corrected.log`.

## Lifecycle, verification, and shutdown

After stopping the mage's attack intent, normal logout removed GUID `5` from
the entity registry, spatial state, and metadata. Reconnect restored health
1,875 and flags `36872`, with no combat, attack, cast, references, contact time,
or timer opponent. Metadata agreed. Evidence:
`/tmp/thistle-contact-timers-{logout,reconnect}.log`, `mage-logged-out.png`,
and `mage-reconnected.png`. The later warrior logout was still counting down
when shutdown began; `warrior-logged-out.png` is not completed-logout evidence.

`mix test.all`: **7,204 passed**, 68.4 seconds. Compilation with
`--warnings-as-errors` and strict Credo passed. Logs:
`/tmp/thistle-contact-timers-final-{all,compile,credo}.log`.
Regressions cover overlapping windows, matching versus unrelated opponents,
negative monotonic timestamps, short holds, dead units, incoming versus outgoing
roles, PvP and ownership classification, auto-attack expiry, aura retention,
missed projectile contact, and timer cleanup. Commit hooks also passed.

`/tmp/thistle-contact-timers-server.log` contains no gameplay errors or live
recompilation. Warnings are the existing account-data and GM-ticket opcodes.
WoW PID `2438820` used `amdgpu`; its own graphics counter increased from
`4255783727` to `27553424828` ns. The helper owned
`thistle-wow-playtest.vdT3VA.service`, invocation
`8f6a74c598a84fd1aa46419a4256195f`.

The helper stopped its service and verified inactive/dead. The retained server
exited successfully; WoW PID `2438820` and BEAM PID `2440045` were gone. Logs
and screenshots were retained. No push was performed.
