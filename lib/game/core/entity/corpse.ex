defmodule ThistleTea.Game.Core.Entity.Corpse do
  @moduledoc """
  Corpse entity built from a dead character, including its derived guid and
  the packed equipment display worn at death.
  """
  import Bitwise, only: [|||: 2, <<<: 2]

  alias ThistleTea.Game.Core.Battleground
  alias ThistleTea.Game.Core.Battleground.Insignia
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Corpse, as: CorpseComponent
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Corpse, as: Body
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.ItemTemplate
  alias ThistleTea.Game.Core.Entity.UpdateMask
  alias ThistleTea.Game.Core.Guid

  @update_flag_all 0x10
  @update_flag_has_position 0x40

  @corpse_flag_unk2 0x04
  @equipment_slot_count 19

  defstruct object: %Object{},
            corpse: %CorpseComponent{},
            movement_block: %MovementBlock{},
            internal: %Internal{}

  def guid_for(player_guid) when is_integer(player_guid) do
    Guid.from_low_guid(:corpse, Guid.low_guid(player_guid))
  end

  def build(%Character{} = character, equipped_templates) do
    %{object: object, unit: unit, player: player, internal: internal, movement_block: movement_block} = character
    {x, y, z, o} = movement_block.position

    %__MODULE__{
      object: %Object{
        guid: guid_for(object.guid),
        scale_x: 1.0
      },
      corpse: %CorpseComponent{
        owner: object.guid,
        facing: o,
        pos_x: x,
        pos_y: y,
        pos_z: z,
        display_id: unit.native_display_id || unit.display_id,
        items: pack_items(equipped_templates),
        bytes_1: bytes_1(unit, player),
        bytes_2: bytes_2(player),
        guild_id: 0,
        flags: @corpse_flag_unk2 ||| if(Insignia.available?(character), do: 0x20, else: 0),
        dynamic_flags: 0
      },
      movement_block: %MovementBlock{
        update_flag: @update_flag_all ||| @update_flag_has_position,
        position: {x, y, z, o}
      },
      internal: %Internal{
        world: internal.world,
        corpse_reclaim: internal.corpse_reclaim,
        corpse: %Body{level: unit.level, team: Battleground.team_for_race(unit.race)},
        area: internal.area,
        name: internal.name
      }
    }
  end

  def pack_items(equipped_templates) do
    equipped_templates
    |> Enum.take(@equipment_slot_count)
    |> Enum.with_index()
    |> Enum.reduce(0, fn
      {%ItemTemplate{display_id: display_id, inventory_type: inventory_type}, index}, acc ->
        acc ||| (display_id ||| inventory_type <<< 24) <<< (32 * index)

      {_empty, _index}, acc ->
        acc
    end)
  end

  defp bytes_1(unit, player) do
    UpdateMask.build_bytes([
      {8, 0},
      {8, unit.race},
      {8, unit.gender},
      {8, player.skin}
    ])
  end

  defp bytes_2(player) do
    UpdateMask.build_bytes([
      {8, player.face},
      {8, player.hair_style},
      {8, player.hair_color},
      {8, player.facial_hair}
    ])
  end
end
