defmodule ThistleTea.Game.Entity.Data.Component.Internal do
  @moduledoc """
  Server-only entity state that is never sent to the client: world/area, AI and
  combat bookkeeping, pending events, and casting state. Entity-kind concerns
  live in sub-structs — `Internal.Creature` (creature-template config),
  `Internal.Spawn` (mob spawn/respawn), `Internal.Loot` (mob loot/corpse
  phase), and `Internal.Summon` (summoned game objects) — which stay nil on
  entities they don't apply to.
  """
  alias ThistleTea.Game.WorldRef

  defstruct [
    :home_bind,
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
    :pet,
    :chair,
    :trap,
    :totem,
    :active_pet_entry,
    :active_pet_spell_id,
    :auto_shot,
    :fishing,
    :event,
    :in_combat,
    :threat,
    :threat_refs,
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
    :defense_state_until,
    :defense_target_guid,
    :defense_outcome,
    :combo_expires_at,
    :combo_target_guid,
    :undetectable_until,
    world: WorldRef.open(0),
    rest_bonus: 0.0,
    mailbox: [],
    starting_items: [],
    action_buttons: %{},
    totem_guids: %{},
    cooldowns: %{},
    events: [],
    broadcast_update?: false,
    death_finalized?: false,
    rooted?: false,
    spline_id: 0,
    godmode: false
  ]
end
