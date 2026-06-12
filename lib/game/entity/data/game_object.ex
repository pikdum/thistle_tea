defmodule ThistleTea.Game.Entity.Data.GameObject do
  @moduledoc """
  Game object entity built from Mangos `gameobject` spawn rows and their
  templates.
  """
  import Bitwise, only: [|||: 2]

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.Component.GameObject
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Guid

  @update_flag_all 0x10
  @update_flag_has_position 0x40

  defstruct object: %Object{},
            game_object: %GameObject{},
            movement_block: %MovementBlock{},
            internal: %Internal{}

  @go_state_active 1

  def build_summoned(%Mangos.GameObjectTemplate{} = ot, map, {x, y, z, o}, opts \\ []) do
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
        summoned_by: Keyword.get(opts, :summoned_by),
        use_spell_id: spellcaster_spell(ot),
        spell_charges: spellcaster_charges(ot),
        use_party_only?: spellcaster_party_only?(ot),
        despawn_in_ms: Keyword.get(opts, :despawn_in_ms)
      }
    }
  end

  @go_type_spellcaster 22

  defp spellcaster_spell(%Mangos.GameObjectTemplate{type: @go_type_spellcaster, data0: spell_id})
       when is_integer(spell_id) and spell_id > 0, do: spell_id

  defp spellcaster_spell(_template), do: nil

  defp spellcaster_charges(%Mangos.GameObjectTemplate{type: @go_type_spellcaster, data1: charges})
       when is_integer(charges) and charges > 0, do: charges

  defp spellcaster_charges(_template), do: nil

  defp spellcaster_party_only?(%Mangos.GameObjectTemplate{type: @go_type_spellcaster, data2: data2}) do
    is_integer(data2) and data2 != 0
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
        faction: ot.faction,
        type_id: ot.type,
        anim_progress: o.animprogress
      },
      movement_block: %MovementBlock{
        update_flag: @update_flag_all ||| @update_flag_has_position,
        position: {o.position_x, o.position_y, o.position_z, o.orientation}
      },
      internal: %Internal{map: o.map, event: event}
    }
  end
end
