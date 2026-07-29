defmodule ThistleTea.Game.Entity.Data.GameObject do
  @moduledoc """
  Game object entity built from Mangos `gameobject` spawn rows and their
  templates.
  """
  import Bitwise, only: [|||: 2, &&&: 2]

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.Component.GameObject
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Chair
  alias ThistleTea.Game.Entity.Data.Component.Internal.Fishing
  alias ThistleTea.Game.Entity.Data.Component.Internal.Ritual
  alias ThistleTea.Game.Entity.Data.Component.Internal.Summon
  alias ThistleTea.Game.Entity.Data.Component.Internal.Trap
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate
  alias ThistleTea.Game.Entity.Data.Transport.Pose
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.WorldRef

  @update_flag_transport 0x02
  @update_flag_all 0x10
  @update_flag_has_position 0x40

  defstruct object: %Object{},
            game_object: %GameObject{},
            movement_block: %MovementBlock{},
            internal: %Internal{}

  @go_state_active 1
  @go_state_ready 0
  @go_type_transport 11
  @go_type_mo_transport 15
  @go_flag_transport 0x08
  @go_flag_nodespawn 0x20

  def build_summoned(%GameObjectTemplate{} = ot, world, {x, y, z, o}, opts \\ []) do
    %__MODULE__{
      object: %Object{
        guid: Guid.from_low_guid(:game_object, ot.entry, :erlang.unique_integer([:positive, :monotonic])),
        entry: ot.entry,
        scale_x: ot.size
      },
      game_object: %GameObject{
        created_by: Keyword.get(opts, :summoned_by),
        display_id: ot.display_id,
        flags: ot.flags,
        rotation0: 0.0,
        rotation1: 0.0,
        rotation2: :math.sin(o / 2),
        rotation3: :math.cos(o / 2),
        state: @go_state_active,
        pos_x: x,
        pos_y: y,
        pos_z: z,
        facing: o,
        dyn_flags: 0,
        faction: ot.faction,
        type_id: ot.type,
        level: Keyword.get(opts, :level, 1),
        anim_progress: 100
      },
      movement_block: %MovementBlock{
        update_flag: @update_flag_all ||| @update_flag_has_position,
        position: {x, y, z, o}
      },
      internal: %Internal{
        world: WorldRef.coerce(world),
        chair: chair(ot),
        fishing: Keyword.get(opts, :fishing),
        trap: trap(ot, Keyword.get(opts, :summoned_by)),
        ritual:
          ritual(
            ot,
            Keyword.get(opts, :summoned_by),
            Keyword.get(opts, :ritual_target_guid),
            Keyword.get(opts, :ritual_zone_id)
          ),
        summon: %Summon{
          owner_guid: Keyword.get(opts, :summoned_by),
          despawn_in_ms: Keyword.get(opts, :despawn_in_ms),
          spell_id: spellcaster_spell(ot),
          charges: spellcaster_charges(ot),
          party_only?: spellcaster_party_only?(ot)
        }
      }
    }
  end

  @go_type_spellcaster 22
  @go_type_trap 6
  @go_type_summoning_ritual 18

  defp ritual(%GameObjectTemplate{type: @go_type_summoning_ritual, data: data}, owner_guid, target_guid, zone_id) do
    %Ritual{
      owner_guid: owner_guid,
      target_guid: target_guid,
      zone_id: zone_id,
      required_participants: max(Enum.at(data, 0) || 1, 1),
      completion_spell_id: positive(Enum.at(data, 1)),
      animation_spell_id: positive(Enum.at(data, 2)),
      persistent?: enabled?(Enum.at(data, 3)),
      caster_target_spell_id: positive(Enum.at(data, 4)),
      caster_target_spell_targets: Enum.at(data, 5) || 0,
      casters_grouped?: enabled?(Enum.at(data, 6)),
      no_target_check?: enabled?(Enum.at(data, 7)),
      users: MapSet.new([owner_guid])
    }
  end

  defp ritual(_template, _owner_guid, _target_guid, _zone_id), do: nil

  defp positive(value) when is_integer(value) and value > 0, do: value
  defp positive(_value), do: nil

  defp enabled?(value), do: value == 1

  defp trap(%GameObjectTemplate{type: @go_type_trap, data: data}, owner_guid) do
    %Trap{
      owner_guid: owner_guid,
      radius: trap_radius(Enum.at(data, 2)),
      spell_id: Enum.at(data, 3),
      charges: max(Enum.at(data, 4) || 1, 1),
      start_delay_ms: max(Enum.at(data, 7) || 0, 0) * 1_000
    }
  end

  defp trap(_template, _owner_guid), do: nil

  defp trap_radius(radius) when is_number(radius) and radius > 0, do: min(radius * 1.0, 2.5)
  defp trap_radius(_radius), do: 2.5

  defp spellcaster_spell(%GameObjectTemplate{type: @go_type_spellcaster, data: data}) do
    case Enum.at(data, 0) do
      spell_id when is_integer(spell_id) and spell_id > 0 -> spell_id
      _ -> nil
    end
  end

  defp spellcaster_spell(_template), do: nil

  defp spellcaster_charges(%GameObjectTemplate{type: @go_type_spellcaster, data: data}) do
    case Enum.at(data, 1) do
      charges when is_integer(charges) and charges > 0 -> charges
      _ -> nil
    end
  end

  defp spellcaster_charges(_template), do: nil

  defp spellcaster_party_only?(%GameObjectTemplate{type: @go_type_spellcaster, data: data}) do
    case Enum.at(data, 2) do
      data2 when is_integer(data2) -> data2 != 0
      _ -> false
    end
  end

  defp spellcaster_party_only?(_template), do: false

  def build(%Mangos.GameObject{game_object_template: %Mangos.GameObjectTemplate{} = ot} = o) do
    event =
      case o.game_event_game_object do
        %Mangos.GameEventGameObject{event: event} -> event
        _ -> nil
      end

    %__MODULE__{
      object: %Object{
        guid: Guid.from_low_guid(guid_type(ot.type), o.id, o.guid),
        entry: o.id,
        scale_x: ot.size
      },
      game_object: %GameObject{
        display_id: ot.display_id,
        flags: transport_flags(ot),
        rotation0: o.rotation0,
        rotation1: o.rotation1,
        rotation2: o.rotation2,
        rotation3: o.rotation3,
        state: transport_state(ot, o.state),
        pos_x: o.position_x,
        pos_y: o.position_y,
        pos_z: o.position_z,
        facing: o.orientation,
        dyn_flags: chest_dyn_flags(ot),
        faction: ot.faction,
        type_id: ot.type,
        level: transport_pause(ot),
        anim_progress: o.animprogress
      },
      movement_block: %MovementBlock{
        update_flag: transport_update_flag(ot.type),
        position: {o.position_x, o.position_y, o.position_z, o.orientation},
        stationary_position: transport_stationary_position(ot.type, o),
        transport_progress_in_ms: transport_progress(ot.type)
      },
      internal: %Internal{
        world: WorldRef.open(o.map),
        chair: chair(ot),
        event: event,
        fishing: fishing_hole(ot),
        loot: chest_loot(ot),
        spawn: chest_spawn(ot, o)
      }
    }
  end

  def build_transport(%GameObjectTemplate{} = template, %Pose{map_id: map_id} = pose) when is_integer(map_id) do
    {x, y, z, orientation} = pose.position

    %__MODULE__{
      object: %Object{
        guid: Guid.from_low_guid(:mo_transport, template.entry),
        entry: template.entry,
        scale_x: template.size
      },
      game_object: %GameObject{
        display_id: template.display_id,
        flags: template.flags,
        rotation0: 0.0,
        rotation1: 0.0,
        rotation2: :math.sin(orientation / 2),
        rotation3: :math.cos(orientation / 2),
        state: @go_state_ready,
        pos_x: x,
        pos_y: y,
        pos_z: z,
        facing: orientation,
        dyn_flags: 0,
        faction: template.faction,
        type_id: @go_type_mo_transport,
        level: 0,
        anim_progress: 100
      },
      movement_block: %MovementBlock{
        update_flag: @update_flag_transport ||| @update_flag_all ||| @update_flag_has_position,
        position: pose.position,
        stationary_position: {0.0, 0.0, 0.0, orientation},
        transport_progress_in_ms: pose.progress_ms
      },
      internal: %Internal{world: WorldRef.open(map_id)}
    }
  end

  def transport?(%__MODULE__{game_object: %GameObject{type_id: type}}) do
    type in [@go_type_transport, @go_type_mo_transport]
  end

  defp guid_type(@go_type_transport), do: :transport
  defp guid_type(_type), do: :game_object

  defp transport_flags(%Mangos.GameObjectTemplate{type: @go_type_transport, flags: flags}) do
    flags ||| @go_flag_transport ||| @go_flag_nodespawn
  end

  defp transport_flags(%Mangos.GameObjectTemplate{flags: flags}), do: flags

  defp transport_state(%Mangos.GameObjectTemplate{type: @go_type_transport, data1: start_open}, _state) do
    if start_open == 0, do: @go_state_ready, else: @go_state_active
  end

  defp transport_state(%Mangos.GameObjectTemplate{}, state), do: state

  defp transport_pause(%Mangos.GameObjectTemplate{type: @go_type_transport, data0: pause}), do: pause
  defp transport_pause(%Mangos.GameObjectTemplate{}), do: nil

  defp transport_update_flag(@go_type_transport) do
    @update_flag_transport ||| @update_flag_all ||| @update_flag_has_position
  end

  defp transport_update_flag(_type), do: @update_flag_all ||| @update_flag_has_position

  defp transport_stationary_position(@go_type_transport, %Mangos.GameObject{} = game_object) do
    {game_object.position_x, game_object.position_y, game_object.position_z, game_object.orientation}
  end

  defp transport_stationary_position(_type, %Mangos.GameObject{}), do: nil

  defp transport_progress(@go_type_transport), do: 0
  defp transport_progress(_type), do: nil

  @go_type_chest 3
  @go_type_chair 7
  @go_flag_interact_cond 0x4
  @go_dyn_flag_activate 0x1

  defp chest_dyn_flags(%Mangos.GameObjectTemplate{type: @go_type_chest, flags: flags})
       when is_integer(flags) and (flags &&& @go_flag_interact_cond) != 0 do
    @go_dyn_flag_activate
  end

  defp chest_dyn_flags(_template), do: 0

  defp chair(%Mangos.GameObjectTemplate{type: @go_type_chair, data0: slots, data1: height}) do
    %Chair{slots: positive_or_zero(slots), height: chair_height(height)}
  end

  defp chair(%GameObjectTemplate{type: @go_type_chair, data: [slots, height | _rest]}) do
    %Chair{slots: positive_or_zero(slots), height: chair_height(height)}
  end

  defp chair(_template), do: nil

  defp positive_or_zero(value) when is_integer(value), do: max(value, 0)
  defp positive_or_zero(_value), do: 0

  defp chair_height(value) when value in 0..2, do: value
  defp chair_height(_value), do: 0

  defp chest_loot(%Mangos.GameObjectTemplate{type: @go_type_chest} = ot) do
    case ot.data1 do
      loot_id when is_integer(loot_id) and loot_id > 0 ->
        %Internal.Loot{id: loot_id, min_gold: ot.mingold || 0, max_gold: ot.maxgold || 0}

      _no_loot ->
        nil
    end
  end

  defp chest_loot(_template), do: nil

  @go_type_fishing_hole 25

  defp fishing_hole(%Mangos.GameObjectTemplate{type: @go_type_fishing_hole} = ot) do
    min_uses = max(ot.data2 || 1, 1)
    max_uses = max(ot.data3 || min_uses, min_uses)

    %Fishing{loot_id: ot.data1, uses_left: Enum.random(min_uses..max_uses), ready?: true}
  end

  defp fishing_hole(_template), do: nil

  defp chest_spawn(%Mangos.GameObjectTemplate{type: type}, %Mangos.GameObject{} = o)
       when type in [@go_type_chest, @go_type_fishing_hole] do
    case o.spawntimesecsmin do
      seconds when is_integer(seconds) and seconds > 0 -> %Internal.Spawn{respawn_delay_ms: seconds * 1000}
      _instant -> nil
    end
  end

  defp chest_spawn(_template, _row), do: nil
end
