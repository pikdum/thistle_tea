# Class-specific healing set buffs

Validated with the build-5875 client on 2026-09-26 (America/Chicago).
Implementation: `bc0a2b6a`.
Reference: `refs/vmangos` at `8f4e608450460efe1e38743e4da74397d4773a3a`,
particularly `Unit::HandleDummyAuraProc` for spells 28789 and 28823,
supported-build `spell_proc_event` rows, and the DBC spell and item-set rows.

## Behavior

Redemption Armor's six-piece Holy Power and The Earthshatterer's six-piece
Totemic Power previously installed inert dummy auras. Successful healing now
selects the corresponding buff from the healed recipient's class. The target
owner includes its class in resolved spell feedback; pure aura logic chooses
the spell, and normal triggered-spell delivery applies it to that recipient.
The healer never directly changes another entity's state.

Both bonuses retain their 10 percent proc chance and configured spell-family
restrictions: Flash of Light/Holy Light for Holy Power and Lesser Healing
Wave/Healing Wave for Totemic Power. Direct heals, including self-healing and
overhealing, can trigger them. Periodic healing and cast completion do not.
Dead, missing, and unknown-class recipients produce no buff; delivery rechecks
that the target is alive. Shared reactions retain charge and cooldown ownership.

| Recipient class | Holy Power | Totemic Power |
| --- | --- | --- |
| Warrior | 28790: 700 armor | 28827: 700 armor |
| Paladin, priest, shaman, druid | 28795: 28 mana per five seconds | 28824: 28 mana per five seconds |
| Hunter, rogue | 28791: 140 melee and ranged attack power | 28826: 140 melee attack power |
| Mage, warlock | 28793: 80 magic spell damage | 28825: 80 magic spell damage |

These are the effects actually encoded in the supported data. Buff selection
uses class even while shapeshifted. All eight spells last 8 seconds. Repeated
applications refresh their holder without accumulating duplicate bonuses;
expiry and death remove their derived effects. Removing a set piece prevents
new procs while an already delivered recipient buff keeps its own duration.

## Native acceptance

Two isolated hardware-rendered clients used level-60 Debugpaladin (GUID 2)
with Debugbidder (mage, GUID 11), followed by Debugshaman (GUID 8) with
Debugrival (warrior, GUID 12). Acceptance ran near
`{16303.2, 16218.1, 69.44}` on map 451 with godmode disabled. Existing developer
commands supplied levels, equipment, position, and health/mana setup. Native
clients equipped the items, cast heals, removed equipment, and logged out and
back in. Tidewave probes only read authoritative state.

| Scenario | Client and authoritative evidence |
| --- | --- |
| Redemption equipment | Items 22426 through 22431 occupied six distinct equipment slots. The paladin owned exactly one 28789 holder with source `{:item_set, 528, 28789}`. |
| Heal a mage | Native Flash of Light triggered 28793 on GUID 11, sourced from GUID 2. The mage's fire spell bonus increased from 12 to 92 while armor and attack power stayed unchanged. Both clients showed the recipient buff. |
| Expiry and set removal | Removing the paladin's headpiece removed the set holder. Another Flash of Light still healed the mage; the recorded health was 2018 after setup at 1500. The mage had no Holy Power holder and its fire bonus returned to 12. |
| Reconnect | Re-equipping the same headpiece restored six pieces. Logout cleared entity registration, world position, and metadata for GUID 2. Reconnect retained the equipment and restored exactly one set source, with godmode still disabled. |
| Earthshatterer equipment | Items 22465 through 22470 occupied six distinct equipment slots. The shaman owned exactly one 28823 holder with source `{:item_set, 527, 28823}`. |
| Heal a warrior | Lesser Healing Wave triggered 28827 on GUID 12, sourced from GUID 8. Armor increased from 5129 to 5829. The receiving client displayed the heal and buff; later state had no buff and armor 5129 again. |
| Self-heal | Lesser Healing Wave on the shaman triggered 28824 on GUID 8, sourced from GUID 8, with `mod_power_regen: 28`. The client displayed Totemic Power and its duration. Final state retained only the set passive after the temporary buff expired. |

The native proc chance remained 10 percent; paced casts continued until the
read-only sampler found the buff. An early Lua automation attempt produced a
client script error and was replaced with ordinary paced cast requests.
Initial shaman setup filled its backpack after four pieces; two displaced seed
items were deleted through the client, then the remaining pieces were added
and equipped. Only the confirmed six-piece state is acceptance evidence.

Native testing exercised the spell-damage, armor, and mana-regeneration
selections. Automated tests cover all nine classes, active-resource changes,
attack-power selection, exact expiry boundaries, refresh, death cleanup,
late recipient death, failed eligibility, and shared charge/cooldown behavior.
No owner errors or spell-validation failures appeared in the server log.

WoW's own `amdgpu` graphics counters increased from 5,467,752,397 to
35,251,068,572 ns for PID 1480211 and from 4,813,910,591 to 32,784,030,201 ns
for PID 1481177. Duplicate file descriptors were not summed.

## Validation and retained evidence

`mix test.all`: **6452 passed**. `mix compile --warnings-as-errors` passed.
`mix credo --strict` reported zero issues across 2364 files. Formatting, diff
checks, and commit hooks passed. DBC integration and VMangos restriction tests
retain separate, mutually exclusive tags.

- Healer session: `/home/pikdum/.cache/thistle-wow-playtest.VYh2xu`.
- Recipient session: `/home/pikdum/.cache/thistle-wow-playtest.UcZ2Ch`.
- Screenshots: both `holy-power.png` and `totemic-power.png` captures,
  recipient `expired.png`, healer `logged-out.png`, `reconnected.png`, and
  `totemic-mana.png`, within the corresponding `screenshots` directories.
- State logs share `/tmp/thistle-healing-power`: `-holy-mage.log`,
  `-unequipped.log`, `-paladin-logout.log`, `-reconnect.log`,
  `-shaman-equipped.log`, `-totemic-warrior.log`, `-armor-expired.log`,
  `-totemic-self.log`, and `-final-state.log`.
- GPU counters: `/tmp/thistle-healing-power-gpu-before.log` and `-gpu-after.log`.
- Server and gates: `/tmp/thistle-healing-power-server.log`, `-focused.log`,
  `-all.log`, `-compile.log`, and `-credo.log`.

Both helper-owned client services and the retained server were stopped after
acceptance. No push was performed.
