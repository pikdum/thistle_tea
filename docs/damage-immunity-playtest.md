# Damage immunity and periodic drains

Damage-immunity aura 40 now protects its configured schools through the shared
damage boundary. Melee resolves immunity before avoidance and reports victim
state 7 without consuming shields or producing hit reactions. Harmful spells
check damage immunity before reflection and effect resolution. Existing damage,
life-leech, and mana-drain auras retain their holders and schedules while immune
ticks emit `SMSG_SPELLORDAMAGE_IMMUNE` instead of damage or resource transfers.
Cancellation, expiry, overlapping sources, and death use the existing aura
transition lifecycle. Spell attributes can bypass all immunity or school
immunity specifically; the latter does not bypass damage-immunity holders.

References: `Unit::IsImmuneToDamage`, `SpellCaster::SpellHitResult`,
`Aura::PeriodicTick`, and melee damage resolution in `refs/vmangos/`.
The packet layout comes from `refs/wow_messages/`.

Two related bugs were fixed:

- Periodic mana drains had a tick handler but never scheduled their first tick.
  They now schedule normally and cap transfers at the target's available mana.
- Periodic life leech healed from nominal damage, including absorption and
  overkill. Healing now uses the health actually lost. Focused tests cover
  complete absorption, partial absorption, and lethal overkill.

The full suite also exposed a duel-test teardown race. ExUnit now supervises
that test's unnamed server instead of racing a liveness check against shutdown.

## Real-client acceptance

Two isolated build-5875 clients ran Debugpaladin (GUID 2) and Debugwarlock
(GUID 6), dueling on Programmer Isle with god mode disabled. Actions used
normal client casts, aura cancellation, and existing developer commands.
Tidewave sampled owner state without modifying it.

- Baseline melee reduced the paladin's health. Casting Self Invulnerability
  (16621, the real Invulnerable Mail proc spell) protected against melee for
  its three-second duration. The sampled health stayed at 2516 during the
  holder's lifetime, then fell to 2451, 2391, and 2334 after expiry.
- Damage Immunity Test (1302) provided longer protection for checking client
  feedback. The attacking client visibly displayed **Immune**.
- Shadowburn rank 1 hit through physical-only Self Invulnerability for 159
  damage. The owner sample retained aura 16621 while health fell from 2516
  to 2357, matching the attacker's floating damage number.
- Corruption rank 5 (11671) ticked for 83 damage before broad protection.
  Both its debuff and the immunity buff remained visible while damage paused.
  After right-click cancellation, the same Corruption holder resumed its
  83-damage ticks and later expired normally. Owner samples separately show
  ordinary regeneration during the pause.
- Drain Mana rank 4 (11703) displayed its channel and target debuff. Owner
  samples recorded 102-mana transfers: caster mana increased from 3403 to
  3505 to 3607 while target mana decreased, with ordinary regeneration and
  the caster's maximum handled separately. The aura ended with the channel.

An initial Drain Mana resisted normally and was repeated. Sanctuary's long
category cooldown prevented using it repeatedly. One attempted Lua helper,
`StopAttack`, was unavailable in the vanilla client; its dialog was dismissed
and target clearing was used instead. These attempts were not counted as
successful acceptance.

The item equipment/proc roll itself was not separately exercised. Overlapping
sources, death, immunity bypass, environmental damage, packet encoding, and
owner/observer delivery have automated coverage. The life-leech accounting
follow-up was verified by focused tests after the client session.

There were no gameplay owner or network exceptions. Existing unimplemented
login requests for account data, raid info, tickets, time, and meeting stones
remain outside this feature. Both clients and the server were stopped before
final automated validation.

## Final validation

- `mix test.all`: 3,035 passed.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.
- Final logs: `/tmp/thistle-damage-immunity-final-{tests,compile,credo}.log`.

## Evidence

- Attacker screenshots: `/home/pikdum/.cache/thistle-wow-playtest.ttQo3H/screenshots/immune-feedback.png`,
  `magic-through-physical-immunity.png`, and `mana-drain-channel.png`.
- Target screenshots: `/home/pikdum/.cache/thistle-wow-playtest.712A8F/screenshots/periodic-protected.png`
  and `periodic-resumed.png`.
- Owner timelines: `/tmp/thistle-damage-immunity-physical.txt`,
  `/tmp/thistle-damage-immunity-magic.txt`,
  `/tmp/thistle-damage-immunity-periodic-resumed.txt`, and
  `/tmp/thistle-damage-immunity-drain-retry.txt`.
- Server log: `/tmp/thistle-damage-immunity-server.log`.
