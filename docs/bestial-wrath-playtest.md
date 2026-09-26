# Bestial Wrath and mechanic immunity

Bestial Wrath now applies the four control-immunity boosts missing from its
ordinary DBC effects. Spell loading preloads these definitions at the boundary;
the pure linked-aura transition owns their creation, refresh, and removal.
Children retain the hunter's caster GUID, their original spell flags, and the
parent application's expiry. The client displays the ordinary Bestial Wrath
buff and red, enlarged pet without exposing the four hidden boosts.

The spell-specific links follow `SpellAuraHolder::HandleSpellSpecificBoosts`
in VMangos revision `8f4e608450460efe1e38743e4da74397d4773a3a`:

| Spell | Mechanic immunities |
| --- | --- |
| 19574 | Stun |
| 24395 | Charm, fear, polymorph |
| 24396 | Banish, freeze, horror |
| 24397 | Root, sleep, snare |
| 26592 | Disorient |

The shared immunity logic now checks spell-wide and individual-effect
mechanics, observes immunity polarity and bypass attributes, consumes charged
whole-spell immunity once, and emits an immune combat result. A blocked effect
does not suppress unrelated effects: Frost Nova can damage an immune pet
without rooting it. Newly applied immunities purge matching controls through
the normal aura transition, including controls matched by active effect
mechanics. Purging requires the spell's purge attribute. Fear Ward has no such
attribute in the local DBC, so it prevents a subsequent fear without cleansing
an existing one. Flare's staged effect merge still purges both concealment types.

## Duration bug found in the native client

The first implementation retained each child's raw 15-second DBC duration.
Bestial Wrath itself lasts 18 seconds. A timed native trace showed all four
boosts disappearing while the parent remained, followed by Polymorph landing
16,994 ms after Bestial Wrath was applied. The pet became a sheep while still
retaining the parent's scale bonus. VMangos's local spell-template rows also
retain the shorter child duration; copying those durations left the gap intact.

Spell-specific boost holders now inherit their parent's expiry. This keeps
control immunity aligned with the DBC description's promise that the enraged
pet cannot be stopped. Ordinary linked passives retain their own lifetimes.
Regression coverage checks immunity at 15 seconds and at the final millisecond,
followed by complete removal at 18 seconds.

## Native acceptance

Two fresh isolated GPU-rendered build-5875 clients used level-50 Debughunter
and the mage Debugbidder on Programmer Isle. The level-49 pet was renamed
Wrathproof through the native client to distinguish it from the nearby wild
wolf. All setup, duel actions, casts, and pet commands came from the clients;
runtime inspection was read-only. The immunity acceptance server ran commit
`cd0bc9a2` with no source changes during the run.

The final timed trace for pet GUID 17383894611314868302 recorded:

- Polymorph landed at the 3,382-ms sample, changing display 161 to 856.
- Bestial Wrath appeared at 5,742 ms, removed Polymorph, restored display 161,
  and raised scale from 1.0 to 1.5. All five holders had caster GUID 7 and
  the same expiry, 18,000 ms after application. The owner saw one buff icon.
- Frost Nova lowered health from 2,138 to 2,116 at 7,711 ms. The pet retained
  no root aura and `rooted?` remained false.
- A later Polymorph was scheduled to complete 17,049 ms after Bestial Wrath's
  application. The mage saw `Immune`; the pet remained a wolf with every boost intact.
- The 23,708-ms sample had removed the parent and all four boosts together,
  restoring scale 1.0. Polymorph landed again at 29,683 ms.

After the ordinary cooldown, Dismiss Pet completed while all five Bestial
Wrath holders were still active. The old pet's process, metadata, and spatial
entry disappeared. Call Pet restored GUID 17383894611314868372 at scale 1.0
with no Bestial Wrath holders, retaining its name, health, and follow command.
Logout removed the owner and both prior pet GUIDs. Reconnect restored GUID
17383894611314868410 with the same clean state. Final disconnect removed both
players and every observed pet from process, metadata, and spatial lookup.

## Pet combat reset follow-up

Inspecting the same lifecycle exposed missing permanent pet passives. A focused
regression identified a separate bug: dropping a pet's last threat reference
used the wild creature reset, including on duel completion. That reset removed
permanent passives and could heal the pet or send it toward its spawn. The
reference `PetAI::EnterEvadeMode` performs no wild creature evade cleanup.

Living owned pets now use the existing pet combat cleanup after their last
threat reference disappears. It clears combat and changes attack commands to
follow while retaining stay/follow commands, health, auras, and position.
Wild creatures retain their existing evade behavior. The regression covers
permanent and negative holders and confirms no free heal or home navigation.

A fresh server at commit `9d8ce1d6` repeated the check with two native clients.
The passive-follow run retained every holder, but its threat table was empty.
The decisive second duel therefore used a native `PetAttack()` command:

- The pet entered attack mode with target 11 and an existing threat entry.
- Bestial Wrath applied all five holders. Fireball rank nine lowered health
  from 2,138 to 1,687; its first periodic tick reduced health to 1,674.
- At the 10,866-ms sample, duel completion changed attack to follow, cleared
  combat and threat, and retained health 1,674. All nine passives, all five
  Bestial Wrath holders, and the remaining Fireball aura were unchanged.
- Ordinary regeneration occurred later, at 11,385 ms. Bestial Wrath expired
  normally, leaving all nine permanent passives intact.

Final disconnect removed both players and the pet from process, metadata, and
spatial lookup. All six owned client services across the three server runs
ended inactive/dead, all six WoW processes exited, and all three retained server
sessions exited. Ports 4000, 3724, and 8085 were empty. No server logged errors
or cast-validation failures; warnings were the existing account-data,
GM-ticket, and meeting-stone opcodes.

## Automated validation

- `mix test.all`: 6,651 passed in 61.2 seconds.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.
- Focused linked-aura and Bestial Wrath tests: 22 passed.
- Focused pet, mob, and duel tests: 74 passed, one map-tagged test excluded;
  the full suite above included it.
- `git diff --check` and commit hooks: passed.

Automated coverage also checks existing fear, stun, root, disorient, freeze,
and polymorph cleansing; unchanged damage and scale bonuses; original caster
attribution; refresh; every parent-removal cause; consumed-child preservation;
and death cleanup. No architecture dependency allowlist was expanded.

## Retained evidence

Screenshots remain under `/home/pikdum/.cache/thistle-wow-playtest.SESSION/`:

| Run | Hunter session | Mage session |
| --- | --- | --- |
| Initial duration-gap reproduction | HlOzyD | 72hL36 |
| Immunity and pet lifecycle acceptance | RUeMUN | PY1AU1 |
| Pet combat reset acceptance | gQ68Ac | leP0r1 |

WoW's own DRM graphics counters advanced on each client. Duplicate descriptors
were not summed:

| WoW PID | DRM client | Graphics counter before | Graphics counter after |
| --- | --- | --- | --- |
| 1694855 | 4992 | 508,837,720 ns | 17,421,692,758 ns |
| 1694868 | 4993 | 516,841,819 ns | 16,642,789,435 ns |
| 1703932 | 5078 | 1,555,274,848 ns | 22,142,139,025 ns |
| 1703936 | 5079 | 1,571,276,252 ns | 22,161,685,387 ns |
| 1713416 | 5138 | 1,551,514,057 ns | 14,329,096,110 ns |
| 1713417 | 5139 | 1,573,555,088 ns | 15,015,329,698 ns |

Runtime evidence uses `/tmp/thistle-bestial-*`: `gap-trace.txt`,
`final-control-trace.txt`, `final-before-dismiss.txt`, `final-dismissed.txt`,
`final-recalled.txt`, `final-logout.txt`, `final-reconnected.txt`,
`final-disconnected.txt`, `reset-engaged-trace.txt`, and `reset-cleanup.txt`.
Final checks use `pet-reset-all.log`, `pet-reset-focused.log`, and
`pet-reset-credo.log`. The server logs are `server.log`, `final-server.log`,
and `pet-reset-server.log` under the same prefix.
