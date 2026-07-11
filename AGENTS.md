# Thistle Tea - AGENTS.md

## Commands

### Build/Test/Lint
- `mix compile --warnings-as-errors` - Compile (warnings are not allowed)
- `mix test` - Run all tests
- `mix test.all` - Run all tests, including DBC, VMangos, and Namigator map integration tests
- `mix test test/path/to/file_test.exs` - Run specific test file
- `mix test test/path/to/file_test.exs:123` - Run specific test at line 123
- `mix credo --strict` - Run linting (must stay at zero issues; enforced as a pre-commit hook via devenv)
- `mix format` - Format code

## Code Style

### Development
- Ensure `mix test` and `mix credo --strict` pass before completing tasks

### Testing
- Use `describe "function/arity" do ... end` to group tests by function
- Use `setup [:named_setup]` for reusable test data
- Keep test names concise and descriptive
- Do not query generated sqlite databases in default tests; `db/vmangos.sqlite` loader smoke tests must be tagged `:vmangos_db` so normal `mix test` excludes them, and `db/dbc.sqlite` is not available in CI
- CI runs `mix test` without VMangos first, then generates the database and runs `mix test --only vmangos_db`; keep default tests independent of VMangos, and tag integration tests that also require the unavailable DBC database with `:dbc_db` instead
- Tests that need namigator map geometry (line of sight, terrain heights) must be tagged `:namigator_maps` (excluded by default; map data is not in CI); run with `mix test --include namigator_maps`

### Imports & Structs
- Use `use ThistleTea.Game.Network.Opcodes, [:SMSG_FOO, :CMSG_BAR]` macro to define opcode attributes
- Pattern match on structs in function heads for type safety: `def foo(%Struct{field: val} = entity, ...)`
- Use struct-update syntax and dot access on structs (`%{s | f: v}`, `s.field`), never `Map.put`/`Map.get` — struct-update raises on an unknown field (type-safe) while `Map.put` silently adds bogus keys. `Map.*` is only for genuine plain maps (`Metadata`/ETS rows, DB rows, ad-hoc maps, or a value that may be a struct *or* a map)
- Entities are composed of component structs (Object, Unit, Player, GameObject, etc.)

### Network Messages
- Server messages: `use ServerMessage, :SMSG_FOO`, implement `to_binary/1`
- Client messages: `use ClientMessage, :CMSG_FOO`, implement `from_binary/1` and `handle/2`
- Use `<<value::little-size(32)>>` binary patterns for packet parsing

### Architecture Patterns
- Functional core / boundary layer split (à la "Designing Elixir Systems with OTP"): the core handles data + logic and stays pure; the boundary handles process orchestration (GenServers, Registries, ETS tables)
- Keep the core pure: functions like `take_damage` operate on entity/component data and return new data — no DB calls, no process sends, no side effects. This makes logic generic across players, mobs, and game objects, and trivially testable
- Database queries live at the boundary, not in the core. Loaders (e.g. `lib/game/world/loader/mob.ex`) query Mangos and translate rows into internal entity structs (e.g. `lib/game/entity/data/mob.ex`); domain code never touches `Mangos.*` schemas directly
- Runtime state is decoupled from the Mangos DB — Mangos is a read-only seed at boundaries, not the system's source of truth at runtime
- No Mangos queries in gameplay paths: loaders cache in ETS (boot preload or lazy + cache); CMSG handlers and game systems answer from those caches, never `Mangos.Repo` per request
- Effects as data: pure logic enqueues `Logic.Event` structs on `entity.internal.events` (`Event.enqueue/2`); the entity's owning process drains them with `EventSink.emit_pending/1`. `EventSink` is a dumb interpreter (event → packet/process message) — no game decisions, no Repo calls, no entity mutations inside `emit`. Boundary code may send direct response packets for queries/UI, but entity-state changes flow through events
- `World.Metadata` is a denormalized ETS read cache (faction, level, alive?, …) so processes can check other entities without IPC; only the entity's owning boundary process writes its own metadata — never write Metadata from `entity/logic`
- Message modules are codecs: `handle/2` parses and dispatches into system modules (`Player.*`, `Spell.*`, `entity/logic/*`); don't grow game systems inside CMSG modules
- No durable persistence by design until feature-complete; everything is wiped on restart. Runtime stores are plain ETS in the `ItemStore` shape (`ItemStore`, `CharacterStore`, `Account`). The player entity is `Entity.Data.Character`; saving means `CharacterStore.put/1`. Don't add disk persistence or reintroduce mnesia
- World systems for cross-cutting concerns (CellActivator, SpatialHash, Pathfinding, GameEvent)
- Network layer abstracts packet handling — use message structs, not raw binaries
- Entity-component inspired design: entities = composition of component structs (Object, Unit, Player, GameObject, …), so one implementation can work across entity types
- Derived stats, never mutated stats: displayed unit fields (stats, resistances, max health/mana, attack power, weapon damage, movement speeds) are outputs of pure recompute functions (`Logic.Stats.recompute/1`, `Logic.MovementStats.recompute/1`) over three canonical inputs — `base_*` fields (naked level/DB values, written by `Player.Stats.apply`, entity builders, and weapon-equip sync), `unit.equipment_bonuses` (computed by `EquipmentStats.resync`), and active auras. To change a stat, write the base input and recompute; never write a derived field directly and never read a current field as an input (lazy "capture base from current" is how stale-snapshot bugs happen). Recompute skips fields whose base inputs are nil, which is how mobs keep their DB maxima/damage untouched
- Single funnel over multi-site bookkeeping: give each piece of truth one owner and one write path, and hang lifecycle effects off a single state *transition* rather than off individual entry points — e.g. run death handling (loot, XP, attacker release, respawn) from the health→0 transition, not from each damage-receiving message handler, so a new damage path (a DoT tick) can't skip it. Don't mirror the same fact across two stores (entity struct + `Metadata`, live state + ETS store, struct position + `SpatialHash`) or maintain a counter inc/dec'd from many call sites that must stay balanced — that drift is how "pinned in combat forever" and "kill via DoT dropped no loot/XP" bugs happen. Prefer deriving on read from one source; a denormalized read cache (`World.Metadata`) is fine for hot paths only if it has a single writer
- Behavior trees are the primary abstraction for AI/action logic — mob combat + movement, player combat + spellcasting, etc. all run through the same framework. Core primitives in `lib/game/entity/logic/ai/bt.ex` (`selector`, `sequence`, `condition`, `action`, with `:success | :failure | :running | {:running, delay_ms}` status) plus a shared `Blackboard` for per-entity scheduling. Mob and player trees (`bt/mob.ex`, `bt/player.ex`) compose shared subtrees like `BT.Combat.melee_sequence` and `BT.Spell.casting_sequence`. Trees are ticked from the entity's owning process (mob GenServer, player network handler) and respect `{:running, delay_ms}` to schedule the next tick — prefer extending existing nodes/subtrees over adding ad-hoc logic in the surrounding GenServers

### Formatting
- No comments in code (keep functions self-documenting via naming); the only exceptions are TODO comments and `# credo:disable-for-next-line` markers where a refactor would hurt clarity
- Every module needs a `@moduledoc`; use `@moduledoc false` for self-explanatory modules (packet messages, ecto schemas, pure field-declaration components)
- Use snake_case for atoms and files, PascalCase for modules
- Use conventional commits

### Error Handling
- Use `rescue` blocks in GenServer handle callbacks to prevent crashes
- Prefer pattern matching and guards for validation
