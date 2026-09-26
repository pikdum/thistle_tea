# Pet autocast and spell-triggered attacks

Pet spells now share usefulness checks between idle and combat behavior.
Dash and Dive wait for a victim and skip targets already within melee reach.
Furious Howl and Tainted Blood wait for combat; attack-cancelling buffs such as
Prowl cannot undo an attack command. Automatic casts also avoid healing full
health, refreshing an existing nonstacking aura effect, or stunning an already
stunned target. Direct-damage spells retain their aura-check exemption.
Fire Shield requires an attacker on its chosen target. Manual spell commands
continue through normal cast validation without these autocast-only rules.

Idle casts now use the spell-list scheduler. An unavailable buff cannot starve
later candidates, and preparing a self buff holds the tree in its casting
branch. Autocast toggles preserve spell-list timer indices. Aura effect keys
come from the entity owner's metadata projection; behavior nodes consume an
immutable observation and add no database, clock, or world dependencies.

Successful pet casts with either combat-initiation attribute issue a typed
`PetSpellAttack` request. Resolution captures the target lifetime, and the owner
rechecks liveness, world, and attackability before using the pet command and
`Engagement` transitions. This includes passive pets. Cancellation takes
precedence, and ordinary player spells do not start automatic melee here.

These rules follow `Spell::CanAutoCast`, `Spell::finish`, and the positive-spell
selection rules in `PetAI::UpdateAI` at VMangos revision
`8f4e608450460efe1e38743e4da74397d4773a3a`. DBC tests cover Growl, Bite, Claw,
Prowl, Furious Howl, Tainted Blood, and all three Dash and Dive ranks. Dash's
30-second recovery is stored in the category cooldown field; the eligibility
check uses the greater of spell and category recovery, matching the reference.

## Native acceptance

An isolated GPU-rendered build-5875 client controlled level-50 Debughunter and
the level-49 Prairie Wolf Alpha on Programmer Isle. The existing loyalty
command supplied training points, then the Beast Training window trained Dash
rank one. Runtime probes only read owner state. No source changed during the
server run.

- Passive follow with Dash autocast enabled kept the ability unused while
  idle: no Dash aura and no cooldown. Teleport restoration retained the setting.
- From 25 yards, a client `PetAttack()` command selected Land Walker. A 50-ms
  sampler saw attack intent at 2,248 ms, Dash at 3,268 ms, and the first melee
  damage at 4,237 ms. The pet remained passive in reaction stance. Screenshots
  show the approach and subsequent melee combat.
- The pet remained in melee after Dash expired. At the later authoritative
  read, its original category cooldown had been ready for 31,771 ms, with no
  Dash aura or second cooldown. Its position remained at the melee endpoint.
- After resetting the encounter, the pet was passive, following, and had no
  victim. `CastPetAction(4)` cast Growl at melee range. At 2,347 ms the sampler
  observed command `:attack`, the Land Walker victim, and combat enabled while
  reaction remained `:passive`. Repeated target-health reductions confirmed
  continuing melee attacks. Dash remained unused at melee range; enabled
  Furious Howl produced its aura and cooldown during combat.
- Back in safety, `CastPetAction(7)` successfully cast Dash while idle. The pet
  retained follow mode and no victim, with the expected aura and 30-second
  category cooldown. The client displayed the pet's Dash buff.
- Dismiss Pet removed the live process, metadata, and spatial entry while
  retaining passive stance and autocast IDs 23099 and 24603. Call Pet restored
  both settings and the trained spell under a new GUID. Logout removed the
  recalled pet and player presence. Reconnect restored an idle, noncombat pet
  with the same spells and settings. Final disconnect removed every pet GUID
  observed during the run.

WoW PID 1649030 used DRM client 4739. Its graphics counter advanced from
3,447,730,259 to 15,278,063,998 ns; duplicate file descriptors were not summed.
The owned service `thistle-wow-playtest.2HAS1o.service` ended inactive/dead,
the WoW process exited, and the retained server was stopped. Ports 4000, 3724,
and 8085 were empty. The server logged no errors or cast-validation failures;
warnings were the existing account-data, GM-ticket, and meeting-stone opcodes.

Evidence is retained under `/home/pikdum/.cache/thistle-wow-playtest.2HAS1o/`
and `/tmp/thistle-pet-autocast-*`. Key reads are `chase.txt`,
`melee-verified.txt`, `growl-before.txt`, `growl.txt`, `growl-after.txt`,
`manual-dash.txt`, `dismissed.txt`, `recalled.txt`, `logged-out.txt`,
`reconnected.txt`, and `disconnected.txt`. The earlier `melee.txt` and
`melee-late.txt` probes failed while formatting mixed cooldown entries; the
corrected `melee-verified.txt` supplies the late-melee evidence.

## Validation

- `mix test.all`: 6,624 passed in 68.3 seconds.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.
- `git diff --check`: passed.

The architecture dependency allowlist was not expanded. Automated tests also
cover target death, respawn and world changes, cancellation priority, triggered
completion, manual casts, partially removed aura effects, stackable and area
auras, full-health healing, spell timer stability, and idle cast scheduling.
