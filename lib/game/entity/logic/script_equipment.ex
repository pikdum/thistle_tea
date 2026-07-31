defmodule ThistleTea.Game.Entity.Logic.ScriptEquipment do
  @moduledoc """
  Applies scripted creature virtual-equipment changes to unit fields.
  """
  import Bitwise, only: [&&&: 2, |||: 2, <<<: 2, >>>: 2]

  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.ItemTemplate

  def apply(%Unit{} = unit, [main_hand, off_hand, ranged]) do
    displays = unpack_displays(unit.virtual_item_slot_display)
    info = unpack_info(unit.virtual_item_info)

    displays =
      [main_hand, off_hand, ranged]
      |> Enum.zip(displays)
      |> Enum.map(fn {item, current} -> display(item, current) end)

    info =
      [main_hand, off_hand, ranged]
      |> Enum.zip(info)
      |> Enum.map(fn {item, current} -> info(item, current) end)

    %{unit | virtual_item_slot_display: pack_displays(displays), virtual_item_info: IO.iodata_to_binary(info)}
  end

  def reset(%Unit{} = unit, %Unit{} = default) do
    %{
      unit
      | virtual_item_slot_display: default.virtual_item_slot_display,
        virtual_item_info: default.virtual_item_info
    }
  end

  defp unpack_displays(value) when is_integer(value) do
    for offset <- [0, 32, 64], do: value >>> offset &&& 0xFFFFFFFF
  end

  defp unpack_displays(_value), do: [0, 0, 0]

  defp pack_displays([main_hand, off_hand, ranged]) do
    main_hand ||| off_hand <<< 32 ||| ranged <<< 64
  end

  defp unpack_info(<<main_hand::binary-size(8), off_hand::binary-size(8), ranged::binary-size(8)>>) do
    [main_hand, off_hand, ranged]
  end

  defp unpack_info(_value), do: [<<0::64>>, <<0::64>>, <<0::64>>]

  defp display(:unchanged, current), do: current
  defp display(nil, _current), do: 0
  defp display(%ItemTemplate{display_id: display_id}, _current), do: display_id

  defp info(:unchanged, current), do: current
  defp info(nil, _current), do: <<0::64>>

  defp info(
         %ItemTemplate{
           class: class,
           subclass: subclass,
           material: material,
           inventory_type: inventory_type,
           sheath: sheath
         },
         _current
       ) do
    <<class, subclass, material, inventory_type, sheath, 0, 0, 0>>
  end
end
