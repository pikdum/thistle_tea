# Thistle Tea - AGENTS.md

## Commands

### Build/Test/Lint
- `mix compile --warnings-as-errors` - Compile (warnings are not allowed)
- `mix test` - Run all tests
- `mix test test/path/to/file_test.exs` - Run specific test file
- `mix test test/path/to/file_test.exs:123` - Run specific test at line 123
- `mix test.watch` - Run tests in watch mode
- `mix credo --strict` - Run linting (must stay at zero issues; enforced as a pre-commit hook via devenv)
- `mix format` - Format code
- `mix build_maps` - Generate navigation meshes from map files

## Code Style

### Development
- Ensure `mix test` and `mix credo --strict` pass before completing tasks

### Testing
- Use `describe "function/arity" do ... end` to group tests by function
- Use `setup [:named_setup]` for reusable test data
- Keep test names concise and descriptive
- Do not query `db/mangos0.sqlite` or `db/dbc.sqlite` in tests; these sqlite databases are not available in CI

### Imports & Structs
- Use `use ThistleTea.Game.Network.Opcodes, [:SMSG_FOO, :CMSG_BAR]` macro to define opcode attributes
- Pattern match on structs in function heads for type safety: `def foo(%Struct{field: val} = entity, ...)`
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
- World systems for cross-cutting concerns (CellActivator, SpatialHash, Pathfinding, GameEvent)
- Network layer abstracts packet handling — use message structs, not raw binaries
- Entity-component inspired design: entities = composition of component structs (Object, Unit, Player, GameObject, …), so one implementation can work across entity types
- Derived stats, never mutated stats: displayed unit fields (stats, resistances, max health/mana, attack power, weapon damage, movement speeds) are outputs of pure recompute functions (`Logic.Stats.recompute/1`, `Logic.MovementStats.recompute/1`) over three canonical inputs — `base_*` fields (naked level/DB values, written by `Player.Stats.apply`, entity builders, and weapon-equip sync), `unit.equipment_bonuses` (computed by `EquipmentStats.resync`), and active auras. To change a stat, write the base input and recompute; never write a derived field directly and never read a current field as an input (lazy "capture base from current" is how stale-snapshot bugs happen). Recompute skips fields whose base inputs are nil, which is how mobs keep their DB maxima/damage untouched
- Behavior trees are the primary abstraction for AI/action logic — mob combat + movement, player combat + spellcasting, etc. all run through the same framework. Core primitives in `lib/game/entity/logic/ai/bt/bt.ex` (`selector`, `sequence`, `condition`, `action`, with `:success | :failure | :running | {:running, delay_ms}` status) plus a shared `Blackboard` for per-entity scheduling. Mob and player trees (`bt/mob.ex`, `bt/player.ex`) compose shared subtrees like `BT.Combat.melee_sequence` and `BT.Spell.casting_sequence`. Trees are ticked from the entity's owning process (mob GenServer, player network handler) and respect `{:running, delay_ms}` to schedule the next tick — prefer extending existing nodes/subtrees over adding ad-hoc logic in the surrounding GenServers

### Formatting
- No comments in code (keep functions self-documenting via naming); the only exceptions are TODO comments and `# credo:disable-for-next-line` markers where a refactor would hurt clarity
- Every module needs a `@moduledoc`; use `@moduledoc false` for self-explanatory modules (packet messages, ecto schemas, pure field-declaration components)
- Use snake_case for atoms and files, PascalCase for modules
- Use conventional commits

### Error Handling
- Use `rescue` blocks in GenServer handle callbacks to prevent crashes
- Prefer pattern matching and guards for validation
