defmodule ThistleTea.Game.Entity.Data.GameObject do
  @moduledoc """
  Game object entity built from Mangos `gameobject` spawn rows and their
  templates.
  """
  import Bitwise, only: [|||: 2, &&&: 2]

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.Component.GameObject
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Fishing
  alias ThistleTea.Game.Entity.Data.Component.Internal.Summon
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate
  alias ThistleTea.Game.Guid

  @update_flag_all 0x10
  @update_flag_has_position 0x40

  defstruct object: %Object{},
            game_object: %GameObject{},
            movement_block: %MovementBlock{},
            internal: %Internal{}

  @go_state_active 1

  def build_summoned(%GameObjectTemplate{} = ot, map, {x, y, z, o}, opts \\ []) do
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
        map: map,
        fishing: Keyword.get(opts, :fishing),
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
        guid: Guid.from_low_guid(:game_object, o.id, o.guid),
        entry: o.id,
        scale_x: ot.size
      },
      game_object: %GameObject{
        display_id: ot.display_id,
        flags: ot.flags,
        rotation0: o.rotation0,
        rotation1: o.rotation1,
        rotation2: o.rotation2,
        rotation3: o.rotation3,
        state: o.state,
        pos_x: o.position_x,
        pos_y: o.position_y,
        pos_z: o.position_z,
        facing: o.orientation,
        dyn_flags: chest_dyn_flags(ot),
        faction: ot.faction,
        type_id: ot.type,
        anim_progress: o.animprogress
      },
      movement_block: %MovementBlock{
        update_flag: @update_flag_all ||| @update_flag_has_position,
        position: {o.position_x, o.position_y, o.position_z, o.orientation}
      },
      internal: %Internal{
        map: o.map,
        event: event,
        fishing: fishing_hole(ot),
        loot: chest_loot(ot),
        spawn: chest_spawn(ot, o)
      }
    }
  end

  @go_type_chest 3
  @go_flag_interact_cond 0x4
  @go_dyn_flag_activate 0x1

  defp chest_dyn_flags(%Mangos.GameObjectTemplate{type: @go_type_chest, flags: flags})
       when is_integer(flags) and (flags &&& @go_flag_interact_cond) != 0 do
    @go_dyn_flag_activate
  end

  defp chest_dyn_flags(_template), do: 0

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
