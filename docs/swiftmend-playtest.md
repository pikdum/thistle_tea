# Swiftmend eligibility and HoT consumption

Implementation: `32f450e0`.
Reference: VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`,
`src/scripts/spells/spell_druid.cpp`, `DruidSwiftmendScript`.

## Behavior

Swiftmend requires Rejuvenation or Regrowth on its recipient. Previously,
the cast could spend mana and start its cooldown without either HoT, then
fall through to a one-point heal. A HoT disappearing before effect delivery
also allowed the ordinary healing calculation to continue.

Admission now uses the existing aura-source projection for other entities
and the caster's own auras for self casts. It returns `target_aurastate`
before resource expenditure or cast packets when neither HoT is present.
The recipient checks its current holders again before healing, excluding
expired holders even when the ordinary aura tick has not removed them yet.
Missing eligible holders produce no healing or healing-threat event.

The existing selection and conversion rules remain: consume the eligible
spell with the shortest remaining duration, regardless of its caster,
and heal four Rejuvenation ticks or six Regrowth ticks plus Swiftmend's
one-point base. Ordinary healing modifiers and critical healing still apply.
Removal uses the shared aura transition, preserving other eligible spells.
The implementation adds no boundary dependencies or architecture exceptions.

## Automated validation

Pure and packet tests cover implicit and explicit self targeting, foreign
recipients and HoT casters, unrelated spell families, missing and expired
holders, selection among multiple HoTs, critical healing, and rejection
without mana expenditure, cooldowns, or spell-start/spell-go packets.

DBC tests exercise all 11 Rejuvenation ranks and all nine Regrowth ranks,
their three-second intervals, exact conversion amounts, consumption,
repeated delivery, and expiry. A separate VMangos-tagged test checks the
Swiftmend script label. Generated database tags remain separate.

The first full run passed 7,430 of 7,431 tests, with a one-second timeout
in the unrelated cell-load retry test. That module then passed 31 consecutive
runs without changes. The final full run passed all 7,431 tests in 68.2
seconds with the same seed, `10493`, and the native clients and server
stopped. Compilation with warnings treated as errors and strict Credo
also passed; Credo reported zero issues. Logs are retained under
`/tmp/thistle-swiftmend-`, including `cell-retry.log`, `final-tests.log`,
`compile.log`, and `credo.log`.

## Native acceptance

Debugdruid (9) and Debugpaladin (2), both level 60, used two isolated
build-5875 clients on Programmer Isle. A fresh server loaded the final code;
there was no live gameplay recompilation. Native debug commands prepared
levels, positions, health, and learned spells. God mode stayed disabled.
Tidewave only read owner state, including 50 ms transition sampling.

- Self and ally casts without a HoT displayed “You can't do that yet.”
  The server reported `target_aurastate`; the initial caster retained all
  2,644 mana and no Swiftmend cooldown.
- Rejuvenation rank 11 supplied a 222-point tick. Swiftmend healed the
  paladin from 1,058 to 1,947, removed Rejuvenation, spent 248 mana, and
  stored a 15,000 ms cooldown.
- With Regrowth and Rejuvenation both active, Swiftmend consumed the
  earlier-expiring Rejuvenation. Health changed from 1,853 to 2,742;
  Regrowth remained and continued its 152-point ticks. The recipient
  displayed the 889-point heal, “Rejuvenation fades,” and the remaining
  Regrowth icon.
- The paladin learned Rejuvenation rank 1 through the native debug command
  to supply a distinct HoT caster. The druid received holder 774 from
  caster 2, then consumed it with self-cast Swiftmend. The client displayed
  a 37-point heal and the fading HoT; the subsequent owner snapshot
  confirmed consumption and the new cooldown.
- Self-cast Regrowth rank 9 supplied 152-point ticks. Swiftmend healed
  1,219 to 2,132 and removed it: exactly `152 * 6 + 1`. The client showed
  913 healing and “Regrowth fades.” Immediate reuse displayed
  “Spell is not ready yet.”
- After another foreign Rejuvenation expired naturally, Swiftmend again
  reported the missing-HoT error. Sampling showed no new mana expenditure,
  Swiftmend healing, or cooldown deadline.

No gameplay errors appeared. Warnings were the expected rejected casts
and existing account-data/GM-ticket stubs.

## Evidence and cleanup

- Druid session: `/home/pikdum/.cache/thistle-wow-playtest.BUEN4E`.
- Paladin session: `/home/pikdum/.cache/thistle-wow-playtest.Yw5BOG`.
- Screenshots include `invalid-self`, `invalid-ally`, `mixed-before`,
  `mixed-after`, `foreign-after`, `regrowth-consumed`, `cooldown-rejected`,
  and `expired-rejected`.
- Owner snapshots and samples: `/tmp/thistle-swiftmend-native-*.log`.
- Server log: `/tmp/thistle-swiftmend-server.log`.
- WoW processes 2789850 and 2790869 each reported `amdgpu`, allocated
  VRAM, and nonzero graphics-engine counters in their own DRM descriptors.

Both helper-owned client services and server process 2790147 were stopped.
Their services were inactive and ports 3724, 8085, and 4000 were closed.
Logs and screenshots were retained. No changes were pushed.
