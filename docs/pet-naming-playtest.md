# Hunter pet naming and abandonment

Hunter pets expose the normal Pet Details, Rename, and Abandon menu. A pet can
receive one chosen name, using two to twelve letters from a supported Latin,
Cyrillic, or East Asian script. Invalid names leave the rename permission intact.
The Vanilla invalid-name packet is empty; it does not use the later expansion's
reason and declined-name fields.

`Companion.name` retains a typed `PetName` with its client cache timestamp.
The player serializes requests, the pet owner process validates ownership and
permission again, and `PetNaming` performs the pure transition. Updating the
timestamp invalidates the name cache even when creation and naming happen in
the same second. The pet publishes its new metadata and update fields;
same-world observers can answer the resulting name query.

Dismissal, owner death, process loss, stabling, and reconnect retain the name and
consumed rename permission. A different or abandoned pet does not inherit it.
The stable window uses the retained chosen name. Abandonment uses the existing
companion suspension and cleanup boundary, then clears the current bond and
client controls without changing pets in the stable. CharacterStore remains
an in-memory runtime store, consistent with the rest of the server.

The protocol and behavior references are VMangos `PetHandler.cpp`, `Pet.cpp`,
`ObjectMgr::CheckPetName`, and the Vanilla pet packet definitions in
`refs/wow_messages/`. Native testing found that publishing the rename bit alone
is insufficient: the client also requires the hunter pet abandon bit to choose
the hunter menu. Both permissions and the abandon handler are now implemented.

## Native acceptance

Two isolated build-5875 GPU clients used Debughunter and Debugbuyer on a fresh
server. All state probes were read-only.

- The hunter renamed Prairie Wolf Alpha to Fang through the pet portrait menu,
  text dialog, and confirmation. Rename disappeared while Pet Details and
  Abandon remained. The observer displayed Fang in its target frame and above
  the pet. The owner, CharacterStore, live pet, and metadata agreed on the name
  and timestamp `1790143788`; the pet number stayed `4194329`.
- Dismiss Pet removed the old process and spatial position. Call Pet created a
  new live GUID with the same chosen name and rename permission already used.
- Jenova Stoneshield's normal stable window displayed Fang. Purchasing a slot,
  dragging the pet into it, and retrieving it retained the name, timestamp,
  pet number, health, and progression.
- Logout saved the suspended named companion. Reconnect created a new pet,
  retained the same name and number, and left the previous process, metadata,
  and spatial position absent.
- Owner death and release removed the live pet while retaining its name in the
  suspended bond. After corpse recovery, Call Pet restored Fang with the same
  name, timestamp, pet number, and consumed rename permission.
- Abandon through the normal menu and confirmation removed the pet bar, current
  bond, owner monitor, live process, metadata, and spatial entry. Call Pet then
  displayed "You do not have a pet". CharacterStore also contained no current
  pet; the purchased stable slot remained.

Both WoW processes used the GPU: their own DRM graphics counters increased from
3.55 to 25.27 billion ns and from 2.75 to 24.55 billion ns. There were no
error-level logs or unsupported pet commands. Existing account-data, raid-info,
GM-ticket, and meeting-stone login warnings were unrelated to these actions.
Both helper-owned client services are inactive, all recorded owned processes
are absent, and the server has stopped with its listeners closed.

Evidence is retained in `/tmp/thistle-pet-naming-*.txt`,
`/tmp/thistle-pet-naming-final-server.log`, and the screenshot directories under
`/home/pikdum/.cache/thistle-wow-playtest.wq0ucO/` (hunter) and
`/home/pikdum/.cache/thistle-wow-playtest.tRaFS5/` (observer).

Automated regressions cover name validity, one-time permission, timestamp
changes, wrong owners, broken bonds, foreign GUIDs, stable retention, old
attachments, abandonment cleanup, packet dispatch and encoding, observer name
queries, world isolation, and loader restoration.

Final validation passed: `mix test.all` (4,951 tests),
`mix compile --warnings-as-errors`, `mix credo --strict`,
`mix format --check-formatted`, and `git diff --check`.

## Rapid map transfer regression

Instance-admission playtesting exposed an unnamed pet becoming "Unknown" when
a teleport landed directly on an instance portal. The client queried the pet
created at the outside entrance after the next world transfer had already
removed it. A process trace captured the request with `ready: false`, no pet
metadata, and no spatial position. The client retained the unresolved name
until reconnect.

The mob now includes its current name response in the companion attachment.
The owner publishes it after creating the pet and sending the pet bar. Every
attachment therefore fills the name cache even when a previous request was
lost during loading. Stable retrieval uses this same projection instead of
sending a separate early name response. The regression test verifies the
name response follows the pet bar without requiring another client query.

On a fresh build-5875 GPU client, teleporting directly to Ragefire Chasm's
open-world entrance and entering through its area trigger retained "Prairie
Wolf Alpha" in both the pet frame and tooltip. Server state agreed on the
template name and retained pet number; the chosen name remained nil.
Repeating the exit and portal entry kept the name visible, retained pet number
4194326, and replaced the live GUID. The previous process, metadata, and spatial
position were all absent. The WoW process's amdgpu graphics counter increased
from 1.82 to 3.51 billion ns. There were no error-level server logs.

The failing trace is `/tmp/thistle-pet-transfer-race.txt`; the before screenshots
are under `/home/pikdum/.cache/thistle-wow-playtest.X43Cwv/`. Fixed screenshots
are under `/home/pikdum/.cache/thistle-wow-playtest.m6DkMC/`, with state evidence
in `/tmp/thistle-pet-transfer-fixed-*.txt` and server logs in
`/tmp/thistle-pet-transfer-fixed-server.log`.

Final follow-up validation passed: `mix test.all` (4,965 tests),
`mix compile --warnings-as-errors`, `mix credo --strict`,
`mix format --check-formatted`, and `git diff --check`. All four client services
used for instance admission and this regression are inactive, no WoW processes
remain, and the server's authentication, world, and HTTP listeners are closed.
