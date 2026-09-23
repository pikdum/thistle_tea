# Spell threat acceptance

Validated on 2026-09-23 against a fresh local server and two GPU-rendered
build-5875 clients on Programmer Isle: Debugwarlock (GUID 6) and Debugpaladin
(GUID 2), both level 60. The target was the seeded Skeletal Flayer
`17379390991937510292`.

## Behavior and reference

`Logic.SpellThreat` projects school, family and critical-damage threat modifiers.
The caster owner publishes that projection through its existing metadata path.
`SpellReception` refreshes threat at impact and supplies current contexts for due
aura ticks through `AIEnvironment` and `BT.Context`. Damage and healing snapshots
remain intact; tick observations do not replace stored aura contexts.

Reference paths in `refs/vmangos/src/game`:

- `Threat/ThreatManager.cpp`, `ThreatCalcHelper::CalcThreat`: spell-family,
  critical-spell and school modifiers.
- `Threat/HostileRefManager.cpp`, `threatAssist`: helpful-threat suppression and
  distribution across hostile references; healing does not set the critical flag.
- `Spells/Spell.cpp`, healing resolution: 0.25 threat per effective point for
  Paladin direct healing, 0.5 for other classes.
- `Spells/SpellAuras.cpp`, periodic healing, leech and power restoration: live
  modifiers, actual gains, and no ordinary periodic mana-regeneration threat in
  1.12. Percentage mana restoration retains its separate threat behavior.

Plagueheart (28746) maps aura 183 to `:mod_critical_threat`. Its separate periodic
spell-family mask comes from the existing VMangos override cache. Database tests
verify the override and DBC behavior separately, using mutually exclusive tags.

## Native results

Actions came from the clients. Read-only Tidewave sampling recorded health,
threat tables, current auras and victims at 200 ms intervals. The client `.threat`
command and target-of-target frame provided independent visible evidence.

| Action | Authoritative result |
| --- | --- |
| Corruption with Plagueheart | Each 10 damage added 7.5 threat. |
| Corruption with Plagueheart and Salvation | Each 10 damage added 5.25 threat. |
| Cancel Salvation during that same Corruption | The next ticks returned to 7.5 threat per 10 damage. |
| Critical Shadow Bolt with Plagueheart | 22 damage added 16.5 threat. |
| Paladin Holy Light | 56 effective healing added 14 threat. |
| Critical Holy Light with Salvation and Plagueheart | 85 effective healing added 14.875 threat, with no critical-damage reduction. |
| Renew with Salvation | Each 10 effective healing added 3.5 threat. |
| Drain Life | Each tick dealt 10 damage, restored 10 health and added 15 total threat. |
| Large critical Holy Light | 1,353 effective healing added 236.775 threat, raising the Paladin from 46.375 to 283.15 and switching the mob's victim from the warlock to the Paladin. |
| Repeat Holy Light at full health | Health and threat stayed unchanged. |

The healer's target had one hostile reference, confirmed through
`Metadata.attacker_count`. The warlock retained 217 threat when the Paladin took
aggro. The observer client displayed both values and the new victim.

Debug setup used existing `.learn` commands for Plagueheart and critical-chance
passives 23434/23440 on the warlock, and 23434/23433 on the Paladin. Read-only
caster contexts confirmed critical chances above 100%. Existing `.modify hp`
prepared healing deficits. No runtime state was mutated through Tidewave.

The second client's `autoSelfCast` setting initially directed helpful casts to
self. Setting it to 0 produced explicit casts on the selected warlock; it was
restored to 1 after testing. The duplicate initial login attempt for the already
connected warlock was refused before selecting the Paladin.

Moving both players beyond the leash reset the Flayer to 2,880 health, target 0,
an empty threat table and no combat. Both players' attacker counts returned to
zero.

Logout removed the warlock's owner, spatial position and metadata. Reconnect
restored Plagueheart's projection with no combat or hostile references. A fresh
Corruption dealt four 10-damage ticks and accumulated exactly 30 threat.

## Evidence

- Warlock session: `/home/pikdum/.cache/thistle-wow-playtest.VmzCNt`.
- Paladin session: `/home/pikdum/.cache/thistle-wow-playtest.y2PScc`.
- Warlock screenshots: `dot-running.png`, `salvation-removed.png`,
  `critical-threat.png`, `leech-threat.png`, `healer-takes-aggro.png`.
  Reconnect evidence: `logged-out.png`, `reconnect-corruption.png`.
- Paladin screenshots: `healing-threat.png`, `critical-healing-salvation.png`.
- Read-only samples: `/tmp/thistle-threat-{dot-native-2,salvation-native,critical-native,healing-native,healing-salvation-native,hot-native,leech-native,overheal-native}.log`.
- Server log: `/tmp/thistle-spell-threat-server.log`.
- Reconnect samples: `/tmp/thistle-threat-reconnect-native.log`.

Both actual `WoW.exe` processes used PCI GPU `0000:0c:00.0`. Process 2377316's
graphics counter increased from 2,753,621,109 to 22,520,460,658 ns; process
2378088's increased from 1,341,009,689 to 20,215,979,734 ns. These measurements
were taken from the game processes' DRM file descriptors.

The run had no gameplay owner crashes. Existing account-data, raid-info,
GM-ticket and meeting-stone unsupported-message warnings appeared at login.
Both helper-owned client services and the retained server were stopped after
acceptance; screenshots and logs were retained.
