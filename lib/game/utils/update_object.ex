defmodule ThistleTea.Game.UpdateObject do
  alias ThistleTea.Game.Utils.NewUpdateObject
  alias ThistleTea.Game.Utils.MovementBlock
  alias ThistleTea.Game.Entities.Data.Object
  alias ThistleTea.Game.Entities.Data.Item

  @item_guid_offset 0x40000000

  # TODO: i really need to clean this up
  def get_item_packets(items) do
    items
    |> Enum.map(fn {_, item} ->
      %NewUpdateObject{
        update_type: :create_object2,
        object_type: :item,
        object: %Object{
          guid: item.entry + @item_guid_offset,
          entry: item.entry
        },
        item: %Item{
          flags: item.flags
        },
        movement_block: %MovementBlock{
          update_flag: 0
        }
      }
      |> NewUpdateObject.to_packet()
    end)
  end
end
