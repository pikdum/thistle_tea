defmodule ThistleTea.Game.Entity.Data.Component.Internal do
  @moduledoc """
  Server-only entity state that is never sent to the client: map/area, AI and
  combat bookkeeping, pending events, and casting state. Entity-kind concerns
  live in sub-structs — `Internal.Spawn` (mob spawn/respawn), `Internal.Loot`
  (mob loot/corpse phase), and `Internal.Summon` (summoned game objects) —
  which stay nil on entities they don't apply to.
  """
  defstruct [
    :map,
    :name,
    :area,
    :spells,
    :spellbook,
    :casting,
    :next_swing_spell,
    :experience_multiplier,
    :extra_flags,
    :rank,
    :spawn,
    :loot,
    :summon,
    :event,
    :in_combat,
    :last_hostile_time,
    :last_mana_use_at,
    :health_regen_carry,
    :running,
    :behavior_tree,
    :blackboard,
    :visibility_cell,
    :movement_start_time,
    :movement_start_position,
    :creature_type_flags,
    :regenerate_stats,
    :pending_resurrect,
    action_buttons: %{},
    cooldowns: %{},
    events: [],
    broadcast_update?: false,
    spline_id: 0,
    godmode: false
  ]
end
