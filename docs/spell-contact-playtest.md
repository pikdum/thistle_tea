# Spell contact and combat acceptance

Implementation: `9fde327f`.
Native-playtest follow-up: `f6414e60`.

## Behavior

Spell reception resolves immunity, reflection, hit avoidance, and mechanic
resistance once, before the owner decides whether to enter combat. The
decision uses the recipient's ability to detect the caster. All launch misses
use the same delivery path, including projectile delay.

An undetected failed Sap stays peaceful. A detected failed Sap enters combat,
even when Improved Sap retains Stealth. Failure-breaks-stealth spells such as
Pick Pocket force the corresponding reveal and combat behavior. Successful
Sap keeps its peaceful exception. Successful hits honor no-initial-threat and
the independent stealth and invisibility exemptions.

Actual damage has its own combat rule. Direct damage and channeled periodic
damage can initiate combat; ordinary periodic ticks, damage shields, and
proc-triggered spells retain their exceptions. Proc feedback no longer owns a
second combat transition. Recipient and caster updates travel through typed
effects and their owning processes. Creature engagement remains owned by
`Logic.Engagement`, including first-damage victim selection and lethal-hit
loot credit.

## Reference and automated checks

The corresponding VMangos rules are in
`refs/vmangos/src/game/Spells/Spell.cpp` (`DoAllEffectOnTarget`,
`DoSpellHitOnUnit`, and `IsTriggeredByProc`) and
`refs/vmangos/src/game/Objects/Unit.cpp` (`DealDamage`). Spell flags and direct
threat-effect classification come from `SpellDefines.h` and `SpellEntry.h`.

After the final code change, all 5,672 tests passed with `mix test.all`.
Compilation with warnings as errors, strict Credo, formatting, and whitespace
checks also passed. Twenty-four added tests cover the contact policy,
recipient preparation, hidden and detected immunity, defensive pets, PvP,
projectile detection, proc classification from real DBC rows, concealment
exceptions, damage and lethal-tick credit, and first-damage victim selection.
The architecture dependency allowlist was not expanded.

## Native Sap acceptance

Two isolated build-5875 clients used hardware OpenGL. WoW PIDs 221517 and
222229 had active amdgpu graphics counters. All setup and gameplay used native
client commands; Tidewave only read state and sampled transitions.

Debugrogue (GUID 3) was level 60 with Improved Sap rank 3 (`14095`) and
Stealth rank 3 (`1786`). Debugbuyer (GUID 10) began at level 45. God mode was
off. A native duel made them hostile. They stood 4.5 yards apart on open map
451, with the target facing the rogue. Limited Invulnerability Potions
(`3387`, aura `3169`) provided six seconds of physical immunity. Each trial
waited for the normal two-minute potion cooldown; no spell outcomes or
talent rolls were forced.

Against the level-45 target, detection was false. Sap (`11297`) spent 65
energy, and the client combat log displayed "Your Sap failed. Debugbuyer is
immune." Both owners stayed out of combat, health stayed unchanged, and the
rogue retained the original Stealth holder and application timestamp. No Sap
aura appeared on the target. Potion expiry left both players peaceful.

After raising the target to level 60, detection was true at the same distance
and facing. One attempt naturally failed Improved Sap's preservation roll:
both players entered combat and Stealth faded. A further unforced attempt
retained Stealth. The recipient entered combat first, followed by the caster
within the next 22-ms sample. The client showed the immune result and combat
entry. Both owners stayed at full health, and the same Stealth holder remained
through combat entry and subsequent combat expiry. These observations verify
the two branches, not the talent's statistical probability.

Conceding the duel and logging out removed both player owners and metadata.
Debugbuyer logged back in with no combat, duel, duel arbiter, Sap, or potion
aura. The original Stealth casting and successful-Sap acceptance remains in
[stealth-casting-playtest.md](stealth-casting-playtest.md).

## Native first-damage acceptance and follow-up

Debugpriest (GUID 4), level 60 with god mode off, learned Starshards rank 1
(`10797`) through the native developer command. The spell has both channeled
and no-initial-threat attributes. The target was the seeded level-4 Defias
Thug, GUID 17379390962661268572, at `{16328.2, 16298.1, 69.4444}` on map 451.
The priest cast from 20 yards away with clear line of sight.

The initial trial proved delayed combat entry and exposed a missing victim:
the first tick established combat and threat, but `unit.target` stayed zero,
preventing the creature's combat subtree from running. The creature took six
15-damage ticks and died without chasing. Death cleared its aura and threat;
respawn restored 86 health and cleared the tap. The follow-up commit fixes
first-damage selection through the existing engagement transition, with
regressions asserting both the victim and attacker notification.

A fresh server on the follow-up commit repeated the test. Aura application
left both owners out of combat. Exactly 1,000 ms later in the sampled trace,
the first 14-damage tick reduced the thug from 86 to 72 health, selected the
priest as victim, established 14 threat, and assigned the priest loot credit.
Within the next 45-ms sample the caster was in combat and the creature was
moving toward them. The client displayed damage, combat entry, and the
thug's target-of-target frame pointing to Debugpriest.

The thug chased from x=16328.2 to x=16312.7, entered melee range, and damaged
the priest. The channel ended after five ticks as melee damage shortened it;
the thug had 16 health. The combat log showed its swings and incoming
three-point hits. After retreat, the thug returned home with 86 health,
target zero, empty threat, no tap, and no aura. The priest recovered full
health, cleared all threat references and combat state, and had channel spell
zero.

## Artifacts and limitations

Local screenshots and client logs remain in:

- `/home/pikdum/.cache/thistle-wow-playtest.Ec81hr`
- `/home/pikdum/.cache/thistle-wow-playtest.pyoKqP`

The useful frames are `hidden-sap-log`, `visible-immune-retained`,
`visible-immune-retained-recipient`, `starshards-chase-fixed`, and
`starshards-melee-fixed`. Read-only traces and gate logs use the
`/tmp/thistle-spell-contact-*` prefix. The first Starshards sampler printed
unchanged rows because of a diagnostic comparison typo; its compacted trace
is retained separately. The final sampler records changes only.

Native evidence covers immune Sap and channeled first damage; the other
policy branches are covered by regression tests. Unsupported client movement
and diagnostic Lua calls were discarded during setup. Gameplay produced no
server errors or spell-validation warnings. Login emitted the existing
unsupported account-data, GM-ticket, and meeting-stone queries.

Final logout removed all three player owners and their metadata. Both
helper-owned client cgroups and both retained server processes were stopped.
No changes were pushed.
