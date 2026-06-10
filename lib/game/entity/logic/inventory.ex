defmodule ThistleTea.Game.Entity.Logic.Inventory do
  import Bitwise, only: [&&&: 2, <<<: 2]

  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate

  @bag_0 255

  @equipment_fields [
    :head,
    :neck,
    :shoulders,
    :body,
    :chest,
    :waist,
    :legs,
    :feet,
    :wrists,
    :hands,
    :finger1,
    :finger2,
    :trinket1,
    :trinket2,
    :back,
    :mainhand,
    :offhand,
    :ranged,
    :tabard
  ]

  @bag_fields [:bag1, :bag2, :bag3, :bag4]
  @backpack_fields Enum.map(1..16, fn i -> String.to_atom("inv#{i}") end)
  @slot_fields @equipment_fields ++ @bag_fields ++ @backpack_fields

  @field_by_slot @slot_fields |> Enum.with_index() |> Map.new(fn {field, index} -> {index, field} end)
  @slot_by_field @slot_fields |> Enum.with_index() |> Map.new()

  @equipment_slot_count length(@equipment_fields)
  @bag_slot_start @equipment_slot_count
  @backpack_slot_start @bag_slot_start + length(@bag_fields)
  @slot_count length(@slot_fields)

  @mainhand_slot @slot_by_field[:mainhand]
  @offhand_slot @slot_by_field[:offhand]

  @invtype_two_hand 17

  @item_flag_indestructible 0x20

  @dual_wield_classes [1, 3, 4]

  @relic_subclass_classes %{0 => 9, 7 => 2, 8 => 11, 9 => 7}

  @error_codes %{
    ok: 0,
    cant_equip_level_i: 1,
    item_doesnt_go_to_slot: 3,
    no_required_proficiency: 8,
    you_can_never_use_that_item: 10,
    cant_equip_with_twohanded: 13,
    cant_dual_wield: 14,
    item_cant_be_equipped: 20,
    items_cant_be_swapped: 21,
    slot_is_empty: 22,
    item_not_found: 23,
    cant_drop_soulbound: 24,
    int_bag_error: 40
  }

  def bag_0, do: @bag_0

  def error_code(error), do: Map.fetch!(@error_codes, error)

  def slots, do: @equipment_fields

  def slot_index(field), do: Map.fetch!(@slot_by_field, field)

  def valid_slot?(slot), do: is_integer(slot) and slot >= 0 and slot < @slot_count

  def equipment_slot?(slot), do: is_integer(slot) and slot >= 0 and slot < @equipment_slot_count

  def bag_slot?(slot), do: is_integer(slot) and slot >= @bag_slot_start and slot < @backpack_slot_start

  def backpack_slot?(slot), do: is_integer(slot) and slot >= @backpack_slot_start and slot < @slot_count

  def visible_entry_field(slot) when is_atom(slot), do: visible_entry_field(slot_index(slot))
  def visible_entry_field(slot) when is_integer(slot), do: :"visible_item_#{slot + 1}_0"

  def visible_entry(%Player{} = player, slot) do
    Map.get(player, visible_entry_field(slot))
  end

  def item_guid(%Player{} = player, slot) when is_integer(slot) do
    with field when is_atom(field) <- Map.get(@field_by_slot, slot),
         guid when is_integer(guid) and guid > 0 <- Map.get(player, field) do
      guid
    else
      _ -> nil
    end
  end

  def equip(%Player{} = player, slot, %Item{} = item) when is_atom(slot) do
    put_slot(player, slot_index(slot), item)
  end

  def equipped_guids(%Player{} = player) do
    @equipment_fields
    |> Enum.map(fn field -> Map.get(player, field) end)
    |> Enum.filter(fn guid -> is_integer(guid) and guid > 0 end)
  end

  def auto_equip(%Player{} = player, %Unit{} = unit, src_slot, get_item) do
    with {:ok, src_item} <- fetch_item(player, src_slot, get_item),
         {:ok, dest} <- find_equip_slot(player, unit, src_item, get_item) do
      if dest == src_slot do
        {:ok, player}
      else
        swap(player, unit, src_slot, dest, get_item)
      end
    else
      {:error, error} -> {:error, error, item_guid(player, src_slot) || 0, 0}
    end
  end

  def swap(%Player{} = player, %Unit{}, slot, slot, _get_item), do: {:ok, player}

  def swap(%Player{} = player, %Unit{} = unit, src_slot, dst_slot, get_item) do
    with {:ok, src_item} <- fetch_item(player, src_slot, get_item),
         dst_item = item_at(player, dst_slot, get_item),
         :ok <- validate_placement(player, unit, src_item, dst_slot, get_item),
         :ok <- validate_placement(player, unit, dst_item, src_slot, get_item),
         :ok <- validate_two_hand(player, src_item, src_slot, dst_slot, dst_item) do
      player =
        player
        |> put_slot(src_slot, dst_item)
        |> put_slot(dst_slot, src_item)
        |> store_offhand_if_two_hand(src_item, dst_slot, get_item)

      {:ok, player}
    else
      {:error, error} -> {:error, error, item_guid(player, src_slot) || 0, item_guid(player, dst_slot) || 0}
    end
  end

  def destroy(%Player{} = player, slot, get_item) do
    with {:ok, item} <- fetch_item(player, slot, get_item),
         :ok <- validate_destructible(item) do
      {:ok, put_slot(player, slot, nil), item}
    else
      {:error, error} -> {:error, error, item_guid(player, slot) || 0, 0}
    end
  end

  def find_equip_slot(%Player{} = player, %Unit{} = unit, %Item{} = item, get_item) do
    template = Item.template(item)

    with :ok <- can_use(unit, template) do
      case candidate_slots(template, unit.class) do
        [] ->
          {:error, :item_cant_be_equipped}

        candidates ->
          free =
            Enum.find(candidates, fn slot ->
              item_guid(player, slot) == nil and not blocked_offhand?(player, slot, get_item)
            end)

          {:ok, free || hd(candidates)}
      end
    end
  end

  def can_use(%Unit{} = unit, %ItemTemplate{} = template) do
    cond do
      (template.allowable_class &&& 1 <<< (unit.class - 1)) == 0 -> {:error, :you_can_never_use_that_item}
      (template.allowable_race &&& 1 <<< (unit.race - 1)) == 0 -> {:error, :you_can_never_use_that_item}
      is_integer(template.required_level) and unit.level < template.required_level -> {:error, :cant_equip_level_i}
      true -> :ok
    end
  end

  def can_dual_wield?(class), do: class in @dual_wield_classes

  def two_hand_used?(%Player{} = player, get_item) do
    case item_at(player, @mainhand_slot, get_item) do
      %Item{} = item -> Item.template(item).inventory_type == @invtype_two_hand
      _ -> false
    end
  end

  defp candidate_slots(%ItemTemplate{inventory_type: inventory_type} = template, class) do
    case inventory_type do
      1 -> [slot_index(:head)]
      2 -> [slot_index(:neck)]
      3 -> [slot_index(:shoulders)]
      4 -> [slot_index(:body)]
      5 -> [slot_index(:chest)]
      20 -> [slot_index(:chest)]
      6 -> [slot_index(:waist)]
      7 -> [slot_index(:legs)]
      8 -> [slot_index(:feet)]
      9 -> [slot_index(:wrists)]
      10 -> [slot_index(:hands)]
      11 -> [slot_index(:finger1), slot_index(:finger2)]
      12 -> [slot_index(:trinket1), slot_index(:trinket2)]
      16 -> [slot_index(:back)]
      13 -> if can_dual_wield?(class), do: [@mainhand_slot, @offhand_slot], else: [@mainhand_slot]
      17 -> [@mainhand_slot]
      21 -> [@mainhand_slot]
      14 -> [@offhand_slot]
      22 -> [@offhand_slot]
      23 -> [@offhand_slot]
      15 -> [slot_index(:ranged)]
      25 -> [slot_index(:ranged)]
      26 -> [slot_index(:ranged)]
      19 -> [slot_index(:tabard)]
      28 -> relic_slots(template, class)
      _ -> []
    end
  end

  defp blocked_offhand?(%Player{} = player, slot, get_item) do
    slot == @offhand_slot and two_hand_used?(player, get_item)
  end

  defp relic_slots(%ItemTemplate{subclass: subclass}, class) do
    if Map.get(@relic_subclass_classes, subclass) == class do
      [slot_index(:ranged)]
    else
      []
    end
  end

  defp validate_placement(_player, _unit, nil, _slot, _get_item), do: :ok

  defp validate_placement(%Player{} = player, %Unit{} = unit, %Item{} = item, slot, get_item) do
    template = Item.template(item)

    cond do
      equipment_slot?(slot) ->
        with :ok <- can_use(unit, template) do
          cond do
            slot not in candidate_slots(template, unit.class) -> {:error, :item_doesnt_go_to_slot}
            slot == @offhand_slot and two_hand_used?(player, get_item) -> {:error, :cant_equip_with_twohanded}
            true -> :ok
          end
        end

      backpack_slot?(slot) ->
        :ok

      true ->
        {:error, :item_doesnt_go_to_slot}
    end
  end

  defp validate_two_hand(%Player{} = player, %Item{} = src_item, src_slot, dst_slot, dst_item) do
    if equipping_two_hand?(src_item, dst_slot) and item_guid(player, @offhand_slot) != nil and
         not offhand_storable?(player, src_slot, dst_item) do
      {:error, :cant_equip_with_twohanded}
    else
      :ok
    end
  end

  defp store_offhand_if_two_hand(%Player{} = player, %Item{} = src_item, dst_slot, get_item) do
    with true <- equipping_two_hand?(src_item, dst_slot),
         %Item{} = offhand_item <- item_at(player, @offhand_slot, get_item),
         free_slot when is_integer(free_slot) <- free_backpack_slot(player) do
      player
      |> put_slot(@offhand_slot, nil)
      |> put_slot(free_slot, offhand_item)
    else
      _ -> player
    end
  end

  defp equipping_two_hand?(%Item{} = item, dst_slot) do
    dst_slot == @mainhand_slot and Item.template(item).inventory_type == @invtype_two_hand
  end

  defp offhand_storable?(%Player{} = player, src_slot, dst_item) do
    free_backpack_slot(player) != nil or (backpack_slot?(src_slot) and dst_item == nil)
  end

  defp free_backpack_slot(%Player{} = player) do
    Enum.find(@backpack_slot_start..(@slot_count - 1), fn slot ->
      item_guid(player, slot) == nil
    end)
  end

  defp validate_destructible(%Item{} = item) do
    if (Item.template(item).flags &&& @item_flag_indestructible) == 0 do
      :ok
    else
      {:error, :cant_drop_soulbound}
    end
  end

  defp fetch_item(%Player{} = player, slot, get_item) do
    with true <- valid_slot?(slot),
         %Item{} = item <- item_at(player, slot, get_item) do
      {:ok, item}
    else
      _ -> {:error, :item_not_found}
    end
  end

  defp item_at(%Player{} = player, slot, get_item) do
    case item_guid(player, slot) do
      guid when is_integer(guid) -> get_item.(guid)
      _ -> nil
    end
  end

  defp put_slot(%Player{} = player, slot, nil) do
    player
    |> Map.put(Map.fetch!(@field_by_slot, slot), 0)
    |> put_visible_entry(slot, 0)
  end

  defp put_slot(%Player{} = player, slot, %Item{object: %Object{guid: guid, entry: entry}}) do
    player
    |> Map.put(Map.fetch!(@field_by_slot, slot), guid)
    |> put_visible_entry(slot, entry)
  end

  defp put_visible_entry(%Player{} = player, slot, entry) do
    if equipment_slot?(slot) do
      Map.put(player, visible_entry_field(slot), entry)
    else
      player
    end
  end
end
