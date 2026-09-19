# Resource regeneration across shapeshifts

Player mana, energy, and rage now update independently of the displayed power
bar. Druids recover mana in Cat, Bear, and Dire Bear Form; energy also recovers
while hidden. Rage decays out of combat unless an aura prevents it. Each
reserve retains its existing rate, modifiers, limits, and combat rules.

The scheduler now considers hidden reserves, so full cat energy or zero bear
rage cannot put depleted mana to sleep. Rage that cannot decay no longer
requests a resource tick by itself. Creatures and hunter-pet focus retain
their separate regeneration rules and intervals.

This follows `Player::RegenerateAll` and `Player::Regenerate` in
`refs/vmangos/src/game/Objects/Player.cpp`. The implementation stays in the
pure `Logic.Regen` module and uses the existing behavior-runner maintenance
and player scheduling paths.

## Automated acceptance

Thirteen added tests cover simultaneous reserve updates, the five-second
rule, energy spending without delaying mana recovery, Innervate, Reflection,
independent caps, absent reserves, corpses, ghosts, and scheduler wakeups.
DBC-tagged cases load actual Cat, Bear, Dire Bear, Reflection, and Innervate
spells and exercise aura application, cancellation, expiry, death, and
resurrection. The behavior-runner test checks exact two-second deadlines
before and after cat energy fills.

`mix test.all` passed all 3,334 tests. `mix compile --warnings-as-errors` and
`mix credo --strict` passed. The commit hooks also passed formatting and
strict Credo.

## Real-client acceptance

An isolated build-5875 client controlled the level-50 Debugdruid on Programmer
Isle. Casts, form changes, deaths, release, and corpse recovery went through
the client. Existing developer commands set starting resources and learned
Reflection. Tidewave only read authoritative player state.

- In Cat Form, mana remained at 555 during the five-second rule, then
  recovered while the client displayed energy. A later sample showed
  1,185 mana with energy at 100 and another regeneration tick scheduled.
- Returning to caster form displayed 1,255 mana in client chat. Healing Touch
  rank 1 subsequently cast successfully.
- In Dire Bear Form, mana remained at 450 through the five-second rule, then
  rose by 35 per two-second tick: 485, 520, 555, 590. Rage stayed at zero.
- With rank-3 Reflection, Cat Form recovered 5 mana per tick during the
  five-second rule, then 35 afterward. Mana continued from 740 to 775 after
  energy reached 100.
- Innervate remained active through a change into Cat Form. After setting
  hidden mana to zero, recovery produced 176, 352, 528, 704, 880, 1,056, and
  1,232. The first gain occurred within five seconds of the form's mana cost;
  energy independently reached 100. After Innervate expired, the next mana
  ticks were 1,267, 1,302, 1,337, and 1,372, restoring the normal 35-point rate.
- Death removed Cat Form, restored the mana power bar, retained the passive
  Reflection talent, and stopped regeneration. Mana stayed at 1,055 through
  death and spirit release; the corpse and ghost both reported no resource
  regeneration needed. Corpse recovery used the client's resurrection dialog.
  Recovery restored 1,007 mana and 50 energy; subsequent ticks produced
  1,042/70, 1,077/90, and 1,112/100 while the client displayed caster form.

Cancellation, exact expiry boundaries, regeneration during combat, normal
Bear Form, and absent-resource edge cases have deterministic test coverage.
A second observer client was not used.

## Evidence

- Client session: `/home/pikdum/.cache/thistle-wow-playtest.6ZjrD1/`.
- Runtime samples: `/tmp/thistle-power-reserves-client-*.txt`.
- Server log: `/tmp/thistle-power-reserves-server.log`.
- Validation: `/tmp/thistle-power-reserves-{tests,credo,lifecycle}.log`.

The client correctly refused one form change attempted during Innervate's
global cooldown. Ghosts cannot use ordinary say chat, so the existing teleport
command was sent through a self-whisper before reclaiming the corpse.

No gameplay owner errors or server cast-validation failures appeared in the
log. The client emitted existing unsupported account-data, raid-info,
GM-ticket, time-query, meeting-stone, and cancel-trade requests. The isolated
client and retained server were stopped after acceptance.
