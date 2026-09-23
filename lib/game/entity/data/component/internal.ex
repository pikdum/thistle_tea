defmodule ThistleTea.Game.Entity.Data.Component.Internal do
  @moduledoc """
  Server-only entity state that is never sent to the client: world/area, AI and
  combat bookkeeping, pending events, and casting state. Entity-kind concerns
  live in sub-structs — `Internal.Creature` (creature-template config),
  `Internal.Spawn` (mob spawn/respawn), `Internal.Loot` (mob loot/corpse
  phase), and `Internal.Summon` (summoned game objects) — which stay nil on
  entities they don't apply to.
  """
  alias ThistleTea.Game.Entity.Data.Buyback
  alias ThistleTea.Game.Entity.Data.ChatStatus
  alias ThistleTea.Game.Entity.Data.Companion
  alias ThistleTea.Game.Entity.Data.Component.Internal.ObjectAction
  alias ThistleTea.Game.Entity.Data.CorpseReclaim
  alias ThistleTea.Game.Entity.Data.Honor.Damage, as: HonorDamage
  alias ThistleTea.Game.Entity.Data.PetStable
  alias ThistleTea.Game.Entity.Data.Pvp
  alias ThistleTea.Game.Entity.Data.TalentReset
  alias ThistleTea.Game.WorldRef

  defstruct [
    :home_bind,
    :name,
    :area,
    :spells,
    :spellbook,
    :casting,
    :channel_game_object_guid,
    :channel_game_object_owned?,
    :next_swing_spell,
    :creature,
    :spawn,
    :loot,
    :item_loot,
    :summon,
    :pet,
    :mini_pet,
    :guardian,
    :chair,
    :trap,
    :ritual,
    :totem,
    :duel,
    :auto_shot,
    :ranged_attack_at,
    :fishing,
    :gathering,
    :taxi_flight,
    :event,
    :in_combat,
    :threat,
    :threat_refs,
    :last_hostile_time,
    :combat_leash,
    :companion_monitor,
    :last_trade_id,
    :item_logout_at,
    :last_auction_id,
    :last_vendor_purchase_id,
    :last_mana_use_at,
    :next_sober_at,
    :health_regen_carry,
    :running,
    :behavior_tree,
    :blackboard,
    :ai_tick_ref,
    :ai_tick_token,
    :visibility_cell,
    :movement_start_time,
    :movement_start_position,
    :safe_position,
    :movement_speed,
    :movement_options,
    :fall,
    :breath,
    :pending_resurrect,
    :pending_summon,
    :killed_by,
    :rest_type,
    :rest_started_at,
    :rest_logout_at,
    :logout,
    :defense_state_until,
    :defense_target_guid,
    :defense_outcome,
    :combo_expires_at,
    :combo_target_guid,
    :undetectable_until,
    :invincibility_health_threshold,
    world: WorldRef.open(0),
    object_action: %ObjectAction{},
    buyback: %Buyback{},
    chat_status: %ChatStatus{},
    temporary_threat: %{},
    diminishing_returns: %{},
    companion: Companion.none(),
    corpse_reclaim: %CorpseReclaim{},
    guardians: %{},
    guardian_monitors: %{},
    pet_stable: %PetStable{},
    pvp: %Pvp{},
    honor_damage: %HonorDamage{},
    talent_reset: %TalentReset{},
    forgotten_skills: %{},
    rest_bonus: 0.0,
    mailbox: [],
    starting_items: [],
    action_buttons: %{},
    totem_guids: %{},
    cooldowns: %{},
    events: [],
    navigation_intents: [],
    broadcast_update?: false,
    death_finalized?: false,
    rooted?: false,
    spline_id: 0,
    godmode: false
  ]
end
