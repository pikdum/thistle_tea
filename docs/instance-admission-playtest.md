# Instance admission

Dungeon and raid portals use the same copy admission boundary. Raid maps are
classified as instances, so their creatures no longer populate an open-world
copy. Cached map templates supply raid classification and player limits.

The pure admission rules require a raid group for raids, enforce each copy's
capacity, and allow an account to visit five distinct copies within a rolling
hour. Re-entering an existing copy remains allowed and refreshes its timestamp.
Resets, disconnects, and copy cleanup preserve the account's entry history.
Expired entries are pruned on admission and by a periodic boundary timer.

Admission checks run before committing membership, bindings, copy allocation,
or entry history. The instance process serializes competing entrants. A denied
portal or direct teleport leaves the player in place and sends the Vanilla
client error. If admission fails while restoring a saved login location, the
character returns to their home bind. State remains in memory, as elsewhere in
the server. Permanent raid lockouts and encounter-in-progress restrictions are
separate systems and are not implemented by this change.

References are VMangos `AccountMgr::CheckInstanceCount`,
`AccountMgr::AddInstanceEnterTime`, `MapManager::CanPlayerEnter`, and instance
map admission in `Map.cpp`. The build-5875 client accepts the one-byte
`SMSG_TRANSFER_ABORTED` reason used by VMangos `Server/Packets/Misc.cpp`.
`SMSG_RAID_GROUP_ONLY` contains two uint32 values: delay and reason.

## Native acceptance

Two isolated build-5875 GPU clients used Debughunter and Debugbuyer on a fresh
server. Development teleports positioned characters at open-world entrances;
the actual client area triggers performed instance admission. Runtime state
probes were read-only.

- Solo entry at Zul'Gurub's trigger 3928 displayed "You must be in a raid group
  to enter this instance". The hunter remained in map 0; copies and entry
  history stayed empty.
- After inviting Debugbuyer and converting to a raid through the client, both
  players entered map 309, copy 1, owned by party 1. Membership contained both
  GUIDs, and the buyer could see the hunter inside.
- The buyer logged out inside Zul'Gurub. The hunter left the group. On reconnect,
  the buyer appeared at the Northshire home bind on open map 0, at
  `{-8949.95, -132.493, 83.5312}`, with no instance membership.
- The hunter entered Ragefire Chasm through trigger 2230 and reset empty copies
  between visits. Account 1013 accumulated Zul'Gurub copy 1 and Ragefire copies
  2 through 5. Re-entering copy 5 remained allowed and refreshed only that
  timestamp.
- After leaving and resetting copy 5, the next portal attempt displayed
  "You have entered too many instances recently." The hunter remained on open
  map 1. There was no sixth copy or membership, the next copy ID remained 6,
  and all five account history entries remained present.

Both WoW processes used amdgpu: their own graphics counters increased from
9.65 to 10.72 billion ns and from 7.20 to 8.18 billion ns during the shared-copy
check. Client services and the test server were stopped after acceptance.

Evidence is retained in `/tmp/thistle-instance-admission-server.log`,
`/tmp/thistle-instance-admission-denied.txt`, and screenshot directories under
`/home/pikdum/.cache/thistle-wow-playtest.ecphJu/` (hunter) and
`/home/pikdum/.cache/thistle-wow-playtest.zuAvV7/` (buyer). Commands sent during
loading screens were retried after loading; only confirmed entries count above.

Automated regressions cover concurrent capacity admission, shared-account
resolution through CharacterStore, re-entry, exact expiry boundaries, timer
pruning, reset retention, rejected transfer state, login recovery, packet
encoding, and current VMangos raid classifications and player limits.

Validation passed: `mix test.all` (4,964 tests),
`mix compile --warnings-as-errors`, `mix credo --strict`,
`mix format --check-formatted`, and `git diff --check`.
