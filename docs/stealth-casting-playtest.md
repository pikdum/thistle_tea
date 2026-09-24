# Stealth prerequisites and Improved Sap

Spells carrying the vanilla `ONLY_STEALTHED` attribute now require an
active stealth aura before admission. This covers rogue and druid openers
and creature casters through the shared validation path. Invisibility and
god mode do not satisfy the requirement. Triggered casts bypass it. The
launch boundary does not recheck a prerequisite that normal preparation
has already consumed.

Improved Sap preserves stealth with the talent's 30/60/90 percent chance.
The owner supplies one percentile roll, and the cast carries the resulting
decision through preparation and completion. Separate interruption passes
therefore do not multiply the talent's probability. Preservation keeps
the existing aura; cancellation, damage, or another removal cannot cause
the cast to restore it. Stealth, Prowl, Vanish, explicit stealth-compatible
spells, and triggered spells retain their interruption exceptions.
Improved Sap preserves only stealth, so unrelated action-sensitive auras
still break. A failure that explicitly breaks stealth overrides retention.

Sap also rejects an already fighting target at initial admission, and a
successful Sap does not itself create combat or threat. Ordinary hostile
openers continue to start combat. These changes use the existing aura,
casting, recipient, and engagement paths.

## Reference and regression evidence

`refs/vmangos/src/game/Spells/Spell.cpp` provides the corresponding rules:
`CheckCast` checks stealth and peaceful targets during strict admission;
`ShouldRemoveStealthAuras` identifies the exemptions and Improved Sap
ranks; preparation and completion interrupt action-sensitive auras;
`DoSpellHitOnUnit` excludes successful Sap from ordinary combat entry.

Implementation `0003bc0a` passed `mix test.all` with 5,648 tests,
`mix compile --warnings-as-errors`, `mix credo --strict` with zero issues,
formatting, and whitespace checks. Seventeen added tests cover exact
talent probability thresholds, strongest-rank selection, player and
creature admission, client error encoding, preparation timing, costs,
launch, cancellation, intervening damage, early and late interruption,
triggered casts, failed casts that break stealth, peaceful targets, and
successful Sap's combat/PvP behavior. Real DBC tests cover rogue and druid
openers, all three Sap and Improved Sap ranks, and stealth exemptions.

## Native acceptance

A fresh server on the implementation commit served an isolated build-5875
client. WoW PID 204977 had active amdgpu graphics counters. All setup and
gameplay used native client input; Tidewave performed read-only sampling.
Debugrogue (GUID 3) was raised to level 60, with god mode off throughout.
The recipient was the seeded level-4 Defias Thug, GUID
17379390962661268572, at `{16328.2, 16298.1, 69.4444}` on open map 451.

Without Improved Sap, rank-3 Sap (`11297`) consumed 65 energy and removed
Stealth. The client displayed the Sap debuff and its "Incapacitated"
tooltip. Sampling found health unchanged at 86, no threat or victim, and
both owners out of combat while Sap was active. When Sap later expired
with the rogue still exposed nearby, normal proximity aggro resumed.
Retreating reset the creature before the next trial.

The rogue learned Improved Sap rank 3 (`14095`) through `.learn`, entered
Stealth before approaching, and cast Sap again. An unforced successful
roll consumed 65 energy and retained the original rank-3 Stealth holder
(`1786`), including its unchanged application time. The client displayed
Sap on the creature and the rogue's Stealth tooltip and action bar.
Neither owner entered combat, and the creature retained no threat or
victim. The deterministic tests establish the percentage; this single
native success is not a statistical probability measurement.

The 45-second Sap holder expired and disappeared from the client. The
creature's unit flags returned to zero, with no remaining aura, threat,
victim, or combat state. The original Stealth holder remained unchanged.

Cheap Shot (`1833`) then consumed that retained Stealth and 60 energy,
applied its four-second stun, and put both owners into combat. An
automatic melee swing killed the low-level creature 31 ms after the
first sampled stun state. The client displayed Stealth fading and combat
entry. `/stopattack` is not a vanilla slash command and did not prevent
that swing. Death removed the stun and threat; respawn restored the
creature to 86 health, zero flags, no aura, no threat, and no victim.
After retreat, the rogue had full energy, no combat, and cleared combo
points and target.

Logout and login retained the learned Improved Sap spell and rebuilt its
passive holder. The resulting preservation chance was still 90 percent;
Stealth and combat remained absent. The helper-owned client cgroup was
then stopped, and reads confirmed that the player owner and metadata had
been removed. The retained server was also stopped.

No gameplay validation warnings, server errors, or owner crashes occurred.
Login emitted the existing unsupported account-data, GM-ticket, and
meeting-stone queries; these are unrelated to the tested cast paths.

## Retained evidence

- Client session and screenshots:
  `/home/pikdum/.cache/thistle-wow-playtest.XkGfv3/`.
- Server log: `/tmp/thistle-stealth-casts-server.log`.
- Owner traces: `/tmp/thistle-stealth-casts-untalented.log`,
  `/tmp/thistle-stealth-casts-talented-success.log`,
  `/tmp/thistle-stealth-casts-expiry.log`,
  `/tmp/thistle-stealth-casts-after-expiry.log`,
  `/tmp/thistle-stealth-casts-cheap-shot.log`, and
  `/tmp/thistle-stealth-casts-respawn.log`.
- Reconnect and shutdown: `/tmp/thistle-stealth-casts-reconnect.log` and
  `/tmp/thistle-stealth-casts-shutdown.log`.
- Validation: `/tmp/thistle-stealth-casts-all.log` and
  `/tmp/thistle-stealth-casts-credo.log`.
