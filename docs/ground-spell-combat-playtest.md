# Ground spell combat acceptance

Validated on 2026-09-25 against `c35d4344`, `28cadf54`, and `1d291cd6` with two
native build-5875 clients.

## Corrections

Duel startup assigns the duel state and team without forcing combat. Existing
combat remains intact. This follows `Player::UpdateDuelFlag` in `refs/vmangos`.
A trace of the previous implementation captured a false combat transition at
duel startup, cleared by the next player tick.

Persistent ground refreshes apply their auras without invoking the recipient's
critter escape or EventAI spell-hit reactions, or the caster's spell-hit-target
callback. Actual periodic damage retains its damage and escape reactions.
`DynamicObjectUpdater::VisitHelper` applies persistent auras without those cast
callbacks.

The initial cast also skips persistent effects when delivering unit impacts.
Flare's ground-only implicit target does not enumerate unit hits. Effects that
retain unit targets in spell-go, such as Consecration, still omit those impacts.
Mixed spells such as Flamestrike retain their initial damage. These distinctions
follow `Spell::SetTargetMap`, `Spell::DoAllEffectOnTarget`, and the ground-effect
loop in `Spell.cpp`.

An intermediate native run exposed the initial-cast path after the refresh fix:
`/tmp/thistle-ground-hit-cast-trace.log` records Flare arriving at critters with
two `persistent_area_aura` effects and no persistent source context, followed by
`Critter.spell_hit`. The hunter acquired those critters' threat references without
taking damage. This run prompted the targeting and impact correction.

## Final native acceptance

Debughunter (GUID 7) and Debugbidder (GUID 11) dueled on Programmer Isle, map 451.
The hunter started at `{16303.2, 16318.1, 69.44}`; the mage stood at
`{16309.2, 16324.1, 69.44}`. Both had god mode disabled. The hunter dismissed its
pet before acceptance. All gameplay actions used client input; Tidewave only
observed state and callback returns.

- Both owners transitioned from requested to started duel state without entering
  combat. The hunter callback trace recorded no combat change during startup.
- The mage cast Stealth and disappeared from the hunter's view. Flare revealed
  the mage and applied both dispel immunities to the mage and the three seeded
  rabbits, using two distinct ground sources.
- Neither player entered combat from Flare. The rabbits acquired neither hunter
  threat nor critter escape memory. Rabbit spawn `990002`, runtime GUID
  `17379390974120106802`, retained 1 health throughout the ground spell. The other
  two rabbits repeatedly died and respawned while nearby creatures were active;
  these transitions did not give the hunter threat references.
- At natural expiry, both ground objects and their recipient effects cleared.
  Stealth worked again at the same location and hid the mage from the hunter.
- As a control, the hunter moved beside rabbit `990002` and cast rank-1 Curse of
  Weakness (702). The rabbit retained 1 health, gained the curse and 8 threat
  toward the hunter, and visibly fled. The hunter entered combat with that rabbit
  as its threat reference. About 19 seconds later the fleeing rabbit died;
  its aura, threat, and escape state cleared, the hunter left
  combat, and the rabbit respawned with clean state.

## Evidence and cleanup

The final sessions were `/home/pikdum/.cache/thistle-wow-playtest.ZBjD71` and
`/home/pikdum/.cache/thistle-wow-playtest.8IufhO`. Their `WoW.exe` processes used
`amdgpu` with increasing graphics-engine counters. Screenshots include
`concealed-before-flare`, `final-flare-rabbits`, `final-flare-observer`,
`concealed-after-expiry`, `control-target`, and `direct-curse-flee`.

The server log is `/tmp/thistle-ground-hit-final-server.log`. State evidence is
in `/tmp/thistle-ground-hit-final-{staging,sample,expiry,curse,control-state}.log`;
the duel callback trace is `/tmp/thistle-ground-hit-final-duel-trace.log`.
The server recorded the real duel, Stealth, Flare, and Curse of Weakness casts
without owner errors or failed spell validation. Existing account-data,
GM-ticket, and meeting-stone login warnings remain unrelated to this acceptance.

The duel ended and both players logged out through their clients. Neither player
retained an entity process, metadata, or world position; the duel and the hunter's
Flare source registry were empty. Both helper-owned client services were stopped
and confirmed inactive, and the local server was stopped. Cleanup evidence is in
`/tmp/thistle-ground-hit-final-cleanup.log`.

`mix test.all`: **6,154 passed**. Compilation with warnings as errors and strict
Credo passed. Tests cover idle critters under ground refreshes, periodic damage
escape, recipient and caster EventAI callbacks for mob and player targets,
duel startup with and without existing combat, and actual DBC Flare,
Consecration, and Flamestrike casting behavior.
