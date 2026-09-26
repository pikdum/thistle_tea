# Slow exclusivity acceptance

Simple movement slows and melee attack-speed penalties now replace competing
debuffs by strength and full spell duration. A stronger slow replaces a weaker
one across casters. Equal strength requires at least the existing spell's full
duration, regardless of its remaining lifetime. Weaker applications leave the
holder and its deadline unchanged. Rejecting a slow still allows the same
spell's direct damage to land. Reapplying the same spell can refresh it.

`Spell.Slow` classifies DBC rows and compares compiled base effects through
the shared aura application path. Existing transitions handle removal,
derived stats, speed events, client projection, expiry, and death. Daze and
spells with additional aura types remain outside these categories. Matching
effects can occupy different effect slots. No separate slow state, new
boundary dependency, or architecture allowance was added.

Reference: VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`,
`src/game/Spells/SpellEntry.cpp` `GetSpellSpecific` and
`CompareSpellSpecificAuras`, `SpellEntry.h` `HasSingleAura` and
`IsSingleFromSpellSpecificPerTarget`, and `Objects/Unit.cpp` aura replacement.
Classification preserves the reference's early potion-family handling and
the `PREVENTS_ANIM` daze exemption.

## Native acceptance

Two isolated build-5875 GPU clients ran against commit `1ec6ef4b`.
Debugbidder (GUID 11, level-50 mage) cast on Debugbuyer (GUID 10, level-50
warrior) during an accepted duel on Programmer Isle, map 451. Baseline
recipient movement speed was 7.0 and melee attack interval was 2,100 ms.
Native developer commands granted spells and positioned the characters;
all gameplay mutations used native client input. Tidewave probes were
read-only, including 100 ms state samplers started before the casts.

- Crippling Poison Rank 1 (3409) applied a 50% movement slow for 12 seconds,
  reducing run speed to 3.5. Frost Shock Rank 1 (8056) dealt 114 damage but
  its equal-strength, eight-second slow did not replace the poison or change
  its application or expiry timestamps.
- Crippling Poison Rank 2 (11201) replaced Rank 1 with a 70% slow, reducing
  run speed to 2.1. Frostbolt Rank 1 (116) dealt 28 damage without replacing
  the stronger poison or changing its deadline. Natural expiry restored
  speed to 7.0 with no previous slow returning. `stronger-snare.png` on the
  recipient and `caster-feedback.png` on the caster show the single poison
  debuff; the sampler records damage, speed, and unchanged deadlines.
- Thunderfury (27648) applied a 20% attack-speed penalty, increasing the
  recipient's interval to 2,520 ms. Slow (10371) replaced it with a 25%
  penalty and a shorter duration, increasing the interval to 2,625 ms.
  Recasting Thunderfury left that holder and its deadline unchanged. The
  recipient's native `UnitAttackSpeed("player")` returned
  `2.6250001246808` seconds, visible alongside the single Slow icon in
  `melee-slow.png`. Natural expiry restored 2,100 ms without restoring
  Thunderfury. Run speed stayed at 7.0 throughout this sequence.
- With Rank 2 poison and Slow active together, native `.die` changed health
  from 2,939 to zero, removed both holders, restored run speed from 2.1 to
  7.0, and restored the attack interval from 2,625 to 2,100 ms. Both original
  expiry deadlines were still in the future. `death-cleanup.png` shows the
  death dialog, cancelled duel, and cleared debuff display.

## Automated checks

- `mix test.all`: 6,757 passed in 66.6 seconds.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues across 2,445 source files.
- Focused suite: 153 passed; formatting and pre-commit checks passed.

Coverage includes cross-caster replacement, shorter but stronger effects,
unchanged deadlines on rejection, equal-strength duration comparisons,
same-spell refresh, effects in different slots, daze coexistence, expiry,
death, and retained direct damage. DBC integration tests verify actual
Frostbolt, Cone of Cold, Hamstring, Wing Clip, Crippling Poison, Earthbind,
Concussive Shot, Frost Shock, Piercing Howl, and Thunder Clap rows, as well
as exclusions for Dazed, Enslave Demon, and Barkskin. Native acceptance
does not claim multiple attacking casters, daze coexistence, reconnect,
or every spell variant.

Build and runtime used
`NAMIGATOR_SRC=/nix/store/3nds85i5fyjgpqcgjnk03fdfgs798vfn-namigator-with-wmo-metadata`.

## Retained evidence

Client sessions:

- Caster: `/home/pikdum/.cache/thistle-wow-playtest.RItKQb`.
- Recipient: `/home/pikdum/.cache/thistle-wow-playtest.5zaNP2`.

Screenshots are under each session's `screenshots/` directory. Evidence files
use `/tmp/thistle-slow-exclusivity-` with these suffixes:

- `server.log`, `baseline.txt`, and `snare-trace.txt`.
- `stronger-snare.txt`, `snare-expired.txt`, `melee-trace.txt`, and `melee-slow.txt`.
- `before-death.txt`, `after-death.txt`, and `cleanup.txt`.
- `mage-gpu-start.txt`, `mage-gpu-end.txt`, `buyer-gpu-start.txt`, and `buyer-gpu-end.txt`.
- `test-all.log`, `compile.log`, `credo.log`, and `focused.log`.

Caster WoW PID 1848123 used AMD DRM client 5568; its graphics counter advanced
from 2,152,589,606 ns to 17,837,250,081 ns. Recipient WoW PID 1849016 used
DRM client 5596, advancing from 1,199,739,605 ns to 17,652,411,304 ns.
Duplicate descriptors were counted once. These counters confirm rendering
by both game processes independently of Gamescope.

The server log had no errors or slow-validation warnings. Existing unsupported
account-data, ticket, and meeting-stone requests remained. Both helpers stopped
their recorded service units with matching invocation IDs
`df98c731ac3d4cefa2749e4c5106276c` and `c350d8e554dd44ddbe53fcb187b4576b`.
Both units became inactive with empty cgroups; both players were absent from
their registry, metadata, and world projections. The retained server PTY
exited, all three owned game/server PIDs were absent, and ports 4000, 3724,
and 8085 were free. Artifacts were retained.
