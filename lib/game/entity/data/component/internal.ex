defmodule ThistleTea.Game.Entity.Data.Component.Internal do
  @moduledoc """
  Server-only entity state that is never sent to the client: map/area, AI and
  combat bookkeeping, pending events, and casting state. Entity-kind concerns
  live in sub-structs — `Internal.Creature` (creature-template config),
  `Internal.Spawn` (mob spawn/respawn), `Internal.Loot` (mob loot/corpse
  phase), and `Internal.Summon` (summoned game objects) — which stay nil on
  entities they don't apply to.
  """
  defstruct [
    :map,
    :name,
    :area,
    :spells,
    :spellbook,
    :casting,
    :next_swing_spell,
    :creature,
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
    :ai_tick_ref,
    :ai_tick_token,
    :visibility_cell,
    :movement_start_time,
    :movement_start_position,
    :pending_resurrect,
    :killed_by,
    :rest_type,
    :rest_started_at,
    rest_bonus: 0.0,
    starting_items: [],
    action_buttons: %{},
    cooldowns: %{},
    events: [],
    broadcast_update?: false,
    death_finalized?: false,
    rooted?: false,
    spline_id: 0,
    godmode: false
  ]
end
