defmodule ThistleTea.Game.Core.Entity.Mob do
  @moduledoc """
  Mob entity, including respawn reset and the metadata used for visibility
  queries. `World.Loader.Mob.Builder` builds it from VMangos `creature` rows.
  """
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Core.Aura, as: AuraLogic
  alias ThistleTea.Game.Core.Combat.Engagement
  alias ThistleTea.Game.Core.Combat.Reactive
  alias ThistleTea.Game.Core.Creature.CreatureEntry
  alias ThistleTea.Game.Core.Creature.CreatureFlags
  alias ThistleTea.Game.Core.Creature.CreatureMovement
  alias ThistleTea.Game.Core.Creature.CreatureReaction
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.Internal.Loot
  alias ThistleTea.Game.Core.Entity.Component.Internal.Spawn
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Pet.Companion
  alias ThistleTea.Game.Core.Profession.Skinning
  alias ThistleTea.Game.Core.Stats.MovementStats

  @creature_type_flag_tameable 0x01
  @creature_type_flag_ghost_visible 0x02

  defstruct object: %Object{},
            unit: %Unit{},
            movement_block: %MovementBlock{},
            internal: %Internal{}

  def apply_addon_auras(%__MODULE__{internal: %Internal{creature: %Creature{addon_auras: [_ | _] = spells}}} = mob, now)
      when is_integer(now) do
    Enum.reduce(spells, mob, fn spell, acc ->
      {acc, _events} = AuraLogic.apply_spell(acc, acc.object.guid, acc.unit.level, spell, now)
      acc
    end)
  end

  def apply_addon_auras(%__MODULE__{} = mob, _now), do: mob

  def prepare_summon(%__MODULE__{internal: %Internal{spawn: %Spawn{} = spawn_state} = internal} = mob, opts)
      when is_list(opts) do
    spawn_state = %{
      spawn_state
      | temporary?: true,
        summoner_guid: Keyword.get(opts, :summoner_guid),
        despawn_type: Keyword.get(opts, :despawn_type),
        despawn_delay_ms: Keyword.get(opts, :despawn_delay_ms),
        movement_type: 0,
        waypoint_route: nil
    }

    creature = %{internal.creature | db_guid: nil}

    internal = %{
      internal
      | spawn: spawn_state,
        creature: creature,
        running: Keyword.get(opts, :run?, false) == true
    }

    %{mob | internal: internal}
  end

  @npc_flag_spirit_service 0x60

  def critter?(%__MODULE__{internal: %Internal{pet: nil, totem: nil, creature: %Creature{critter?: true}}}), do: true
  def critter?(_entity), do: false

  def proximity_aggro?(%__MODULE__{internal: %Internal{creature: %Creature{critter?: true}}}), do: false

  def proximity_aggro?(%__MODULE__{} = mob), do: CreatureReaction.mode(mob) == :aggressive

  def visibility_metadata(%__MODULE__{
        object: object,
        unit: %Unit{} = unit,
        internal: %Internal{creature: %Creature{} = creature, loot: loot, name: name}
      }) do
    %{
      entry: object.entry,
      name: name,
      display_id: unit.display_id,
      bounding_radius: unit.bounding_radius,
      combat_reach: unit.combat_reach,
      tameable?: ((creature.type_flags || 0) &&& @creature_type_flag_tameable) != 0,
      detection_range: creature.detection_range,
      db_guid: creature.db_guid,
      npc_flags: unit.npc_flags || 0,
      spirit_service?: ((unit.npc_flags || 0) &&& @npc_flag_spirit_service) != 0,
      ghost_visible?: ((creature.type_flags || 0) &&& @creature_type_flag_ghost_visible) != 0,
      creature_type: creature.creature_type,
      civilian?: creature.civilian?,
      pickpocket_id: if(loot, do: loot.pickpocket_id),
      skinning_id: if(loot, do: loot.skinning_id),
      skinned?: loot && loot.skinned?,
      body_loot?: loot && not is_nil(loot.session)
    }
  end

  def visibility_metadata(%__MODULE__{}), do: %{}

  def respawn(%__MODULE__{} = mob) do
    mob = CreatureEntry.restore(mob)
    internal = mob.internal
    spawn_state = internal.spawn || %Spawn{}
    loot = internal.loot || %Loot{}

    unit = respawn_unit(spawn_state, mob.unit)
    movement_block = respawn_movement_block(spawn_state, mob.movement_block)

    internal = %{
      internal
      | casting: nil,
        invincibility_health_threshold:
          CreatureFlags.invincibility_threshold(mob, internal.invincibility_health_threshold),
        rooted?: false,
        running: false,
        killed_by: nil,
        pve_reward_eligible?: nil,
        death_finalized?: false,
        movement_start_time: nil,
        movement_start_position: nil,
        movement_speed: nil,
        movement_options: nil,
        behavior_tree: nil,
        broadcast_update?: false,
        spawn: %{spawn_state | respawn_ref: nil, respawn_pending?: false, event_data: nil},
        loot: %{loot | session: nil, pockets: nil, skinned?: false, corpse_removed?: false, corpse_token: nil}
    }

    %Engagement.Result{entity: mob} =
      Engagement.reset(%{mob | unit: unit, movement_block: movement_block, internal: internal})

    mob
    |> Reactive.sync_health()
    |> MovementStats.recompute()
    |> CreatureMovement.sync()
    |> Companion.project()
    |> Skinning.sync()
  end

  defp respawn_unit(%Spawn{unit: %Unit{} = unit}, _current_unit), do: unit

  defp respawn_unit(%Spawn{}, %Unit{} = unit) do
    %{
      unit
      | health: unit.max_health,
        power1: unit.max_power1,
        power2: unit.max_power2,
        power3: unit.max_power3,
        power4: unit.max_power4,
        power5: unit.max_power5
    }
  end

  defp respawn_movement_block(%Spawn{movement_block: %MovementBlock{} = movement_block}, _current_movement_block) do
    movement_block
  end

  defp respawn_movement_block(%Spawn{position: {x, y, z}}, %MovementBlock{} = movement_block) do
    %{movement_block | position: {x, y, z, 0.0}, movement_flags: 0}
  end

  defp respawn_movement_block(%Spawn{}, %MovementBlock{} = movement_block) do
    %{movement_block | movement_flags: 0}
  end
end
