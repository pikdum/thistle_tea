# First Aid acceptance

Bandaging now applies Recently Bandaged (11196) to the recipient. Its existing
mechanic-immunity aura prevents another bandage for 60 seconds, including
after interruption. Helpful spells check the target's friendly mechanic
immunities before casting costs, so a rejected bandage consumes no item.
The client receives `SPELL_FAILED_TARGET_AURASTATE` and displays
"You can't do that yet."

The shared aura trigger path recognizes `spell_first_aid` and preserves the
original caster and item GUID. Entity owners publish friendly mechanic
immunities through their existing metadata paths; player and mob cast
contexts carry that immutable projection. Self-target validation reads the
owner's current auras. Hostile spells retain hit-time immunity handling.
No separate First Aid timer, state owner, or architecture allowance was added.

Reference: VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`,
`src/scripts/spells/spell_item.cpp` `FirstAidScript::OnAfterHit`,
`src/game/Spells/Spell.cpp` positive-spell immunity validation, and
`sql/migrations/20251218170610_world.sql` First Aid script bindings.
The real DBC supplies Heavy Runecloth Bandage's eight-second channel,
250 healing per second, and damage interruption; Recently Bandaged supplies
the 60-second mechanic-16 immunity.

## Native acceptance

Two isolated build-5875 GPU clients ran against source `f05ed8c5`.
Debughunter (GUID 7) used native commands to learn Artisan First Aid,
raise skill 129 to 300, and obtain 20 Heavy Runecloth Bandages (14530).
Debugbuyer (GUID 10) was the friendly recipient. Both stood on Programmer
Isle, map 451. Native `.modify hp` supplied health deficits; all acceptance
mutations used client input. Tidewave probes were read-only.

- Self-use consumed one bandage, started spell 18610, and applied 11196.
  The client showed the channel bar, healing feedback, and a one-minute
  debuff. The sampler recorded 250-point healing steps through completion;
  normal regeneration also ran. Health reached its 2,837 maximum and the
  healing aura ended while the lockout retained its original deadline.
  An immediate retry displayed the failure and left 19 bandages.
- Bandaging Debugbuyer consumed one further item. The target showed healing
  and the lockout; the caster saw both target icons. Moving interrupted the
  channel after three healing ticks. The target's healing aura disappeared,
  health stopped receiving 250-point ticks, and Recently Bandaged remained.
  Retrying left 18 bandages and did not refresh the lockout.
- A fresh application consumed the third bandage. After interruption,
  Debugbuyer logged out through the normal 20-second countdown. Its entity,
  metadata, and projected position were absent while CharacterStore retained
  the holder. Login created a new owner with the same application and expiry
  timestamps, original caster and item attribution, and mechanic 16 in
  metadata. The expiry remained 60,000 ms after application, with about
  28 seconds remaining at the reconnect sample. Another rejected attempt
  left 17 bandages, with no healing aura or active channel.
- After natural expiry, both the holder and projected immunity were absent.
  Another native item use consumed exactly one bandage (17 to 16), started
  a new channel, restored healing feedback, and applied a fresh lockout.
  Completion removed the healing aura and active cast; the final sampled
  recipient health was 2,448. The expiry sampler began after the old deadline;
  it records the cleared state and new application, not exact removal timing.

Screenshots include primary `self-bandage.png`, `self-bandage-rejected.png`,
`ally-channel.png`, `ally-rejected.png`, and `after-expiry-channel.png`;
secondary `ally-healing.png`, `retained-lockout.png`, and
`after-expiry-healing.png`. The reconnect screenshot caught early world
loading; authoritative state separately proves the retained deadline.
The first logout attempt stayed offline past expiry and correctly returned
without the debuff; the fresh application above proves active retention.

Native interruption used movement. Deterministic tests cover damage
interruption and a bandaged caster healing a different, eligible recipient.
Native coverage does not claim those two cases or every bandage rank.

## Automated checks

- `mix test.all`: 6,727 passed.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues across 2,434 source files.
- Formatting and pre-commit checks passed.

Tests cover recipient and item attribution, channel completion, damage
interruption, immune-hit rejection without refreshing the holder, self/ally
validation, expiry, immunity bypass attributes, and the actual item-message
path preserving items, cooldowns, and cast state on rejection. Separately
tagged DBC and VMangos tests check ordinary and battleground bandage data.
The first full run exposed an existing raid-cleanup assertion's 100 ms
scheduling race; commit `e185c94e` gives that assertion one second, and the
full rerun passed. Runtime and checks used
`NAMIGATOR_SRC=/nix/store/3nds85i5fyjgpqcgjnk03fdfgs798vfn-namigator-with-wmo-metadata`.

## Runtime evidence

Primary session: `/home/pikdum/.cache/thistle-wow-playtest.Vo6wrt`.
Secondary session: `/home/pikdum/.cache/thistle-wow-playtest.DlIhHc`.
Screenshots are retained under each session's `screenshots/` directory.

WoW PID 1825277 used AMD DRM client 5481; graphics time advanced from
3,120,470,000 ns to 22,309,710,547 ns. WoW PID 1826233 used DRM client 5509;
its counter advanced from 953,141,626 ns to 18,569,326,313 ns. Duplicate
descriptors for each DRM client were counted once.

Evidence files use `/tmp/thistle-first-aid-` with these suffixes:

- `server.log`, `self.txt`, and `ally.txt`.
- `before-logout.txt`, `logged-out.txt`, `reconnected.txt`, and `reconnect-rejected.txt`.
- `expiry.txt`, `after-expiry.txt`, `after-expiry-channel.txt`, and `final-state.txt`.
- `primary-gpu-start.txt`, `primary-gpu-end.txt`, `buyer-gpu-start.txt`, and `buyer-gpu-end.txt`.
- `test-all-final.log`, `compile.log`, and `credo.log`.

The server log contained the three expected `target_aurastate` rejections
and no errors. Existing unsupported account-data, ticket, and meeting-stone
requests remained. Initial read-only inventory diagnostics used incorrect
API shapes and were corrected before collecting acceptance data.

Both helpers stopped their recorded systemd units using invocation IDs
`dfd62023de444c2daa8f0948710ff875` and `1ffed48760b14cef809b240049127d65`.
Both units were inactive with empty cgroups afterward. Neither player
remained in the entity registry, metadata, or projected world position;
`cleanup.txt` records these reads. The retained server PTY exited, the three
owned server/client PIDs were absent, and ports 4000, 3724, and 8085 were free.
