defmodule ThistleTea.Game.Entity.Logic.Inventory do
  @moduledoc """
  Pure player inventory logic over player/unit update fields: equipping,
  storing, swapping, splitting, and destroying items, stack merging, slot
  classification, and equip-slot resolution with class/level/proficiency
  checks. Item lookups are injected as functions so the core stays DB-free.
  """
  import Bitwise, only: [&&&: 2, <<<: 2]

  alias ThistleTea.Game.Entity.Data.Component.Container
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Proficiency

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

  @bag_slots Enum.to_list(@bag_slot_start..(@backpack_slot_start - 1))

  @mainhand_slot @slot_by_field[:mainhand]
  @offhand_slot @slot_by_field[:offhand]

  @invtype_two_hand 17
  @invtype_bag 18

  @item_flag_indestructible 0x20

  @invtype_one_hand 13

  @relic_subclass_classes %{0 => 9, 7 => 2, 8 => 11, 9 => 7}

  @error_codes %{
    ok: 0,
    cant_equip_level_i: 1,
    item_doesnt_go_to_slot: 3,
    nonempty_bag_over_other_bag: 5,
    no_required_proficiency: 8,
    you_can_never_use_that_item: 10,
    cant_equip_with_twohanded: 13,
    cant_dual_wield: 14,
    item_cant_be_equipped: 20,
    items_cant_be_swapped: 21,
    slot_is_empty: 22,
    item_not_found: 23,
    cant_drop_soulbound: 24,
    tried_to_split_more_than_count: 26,
    couldnt_split_items: 27,
    not_a_bag: 30,
    can_only_do_with_empty_bags: 31,
    int_bag_error: 40,
    already_looted: 49,
    inventory_full: 50
  }

  def bag_0, do: @bag_0

  def error_code(error), do: Map.fetch!(@error_codes, error)

  def slots, do: @equipment_fields

  def slot_index(field), do: Map.fetch!(@slot_by_field, field)

  def equipment_slot?(slot), do: is_integer(slot) and slot >= 0 and slot < @equipment_slot_count

  def bag_slot?(slot), do: is_integer(slot) and slot >= @bag_slot_start and slot < @backpack_slot_start

  def backpack_slot?(slot), do: is_integer(slot) and slot >= @backpack_slot_start and slot < @slot_count

  def visible_entry_field(slot) when is_atom(slot), do: visible_entry_field(slot_index(slot))
  def visible_entry_field(slot) when is_integer(slot), do: :"visible_item_#{slot + 1}_0"

  def equip(%Player{} = player, slot, %Item{} = item) when is_atom(slot) do
    equip(player, slot_index(slot), item)
  end

  def equip(%Player{} = player, index, %Item{} = item) when is_integer(index) do
    player
    |> Map.put(Map.fetch!(@field_by_slot, index), item.object.guid)
    |> Map.put(visible_entry_field(index), Item.visible_value(item))
  end

  def equipped_templates(%Player{} = player, get_item) do
    @equipment_fields
    |> Enum.map(fn field -> Map.get(player, field) end)
    |> Enum.filter(fn guid -> is_integer(guid) and guid > 0 end)
    |> Enum.map(get_item)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&Item.template/1)
  end

  def remove_count(%Player{} = player, entry, count, get_item) do
    remove_count(player, entry, count, get_item, %{items: [], destroyed: []})
  end

  defp remove_count(player, _entry, 0, _get_item, acc) do
    {:ok, %{player: player, items: acc.items, destroyed: acc.destroyed}}
  end

  defp remove_count(player, entry, count, get_item, acc) do
    stack =
      player
      |> owned_items(get_item)
      |> Enum.find(fn %Item{object: object} -> object.entry == entry end)

    with %Item{} = stack <- stack,
         pos when pos != nil <- find_position(player, stack.object.guid, get_item) do
      stack_count = stack.item.stack_count || 1

      if stack_count > count do
        {:ok, result} = reduce_stack(player, pos, count, get_item)
        remove_count(result.player, entry, 0, get_item, merge_removal(acc, result, []))
      else
        {:ok, result, destroyed} = destroy(player, pos, get_item)
        remove_count(result.player, entry, count - stack_count, get_item, merge_removal(acc, result, [destroyed]))
      end
    else
      _missing -> {:error, :item_not_found, 0, 0}
    end
  end

  defp merge_removal(acc, result, destroyed) do
    %{items: acc.items ++ result.items, destroyed: acc.destroyed ++ result.destroyed ++ destroyed}
  end

  def count_entry(%Player{} = player, entry, get_item) do
    player
    |> owned_items(get_item)
    |> Enum.filter(fn %Item{object: object} -> object.entry == entry end)
    |> Enum.map(fn %Item{item: item} -> item.stack_count || 1 end)
    |> Enum.sum()
  end

  def owned_items(%Player{} = player, get_item) do
    direct =
      @slot_fields
      |> Enum.map(fn field -> Map.get(player, field) end)
      |> Enum.filter(fn guid -> is_integer(guid) and guid > 0 end)
      |> Enum.map(get_item)
      |> Enum.reject(&is_nil/1)

    contents =
      direct
      |> Enum.filter(&Item.container?/1)
      |> Enum.flat_map(fn bag ->
        bag_slot_guids(bag)
        |> Enum.map(get_item)
        |> Enum.reject(&is_nil/1)
      end)

    direct ++ contents
  end

  def auto_equip(%Player{} = player, %Unit{} = unit, %Proficiency{} = prof, owner_guid, src_pos, get_item) do
    ctx = ctx(player, unit, prof, owner_guid, get_item)

    with {:ok, src_item} <- fetch_item(ctx, src_pos),
         {:ok, dest} <- find_equip_slot(player, unit, prof, src_item, get_item) do
      if {@bag_0, dest} == src_pos do
        {:ok, result(ctx)}
      else
        do_swap(ctx, src_pos, {@bag_0, dest})
      end
    else
      {:error, error} -> {:error, error, guid_at(ctx, src_pos) || 0, 0}
    end
  end

  def swap(%Player{} = player, %Unit{} = unit, %Proficiency{} = prof, owner_guid, src_pos, dst_pos, get_item) do
    ctx = ctx(player, unit, prof, owner_guid, get_item)

    if src_pos == dst_pos do
      {:ok, result(ctx)}
    else
      do_swap(ctx, src_pos, dst_pos)
    end
  end

  def store(%Player{} = player, owner_guid, %Item{} = item, get_item) do
    ctx = ctx(player, nil, nil, owner_guid, get_item)
    {ctx, remaining} = merge_into_stacks(ctx, item)

    cond do
      remaining == 0 ->
        {:ok, result(ctx), :merged}

      free_position(ctx) == nil ->
        {:error, :inventory_full}

      true ->
        pos = free_position(ctx)
        item = put_stack_count(item, remaining)
        ctx = put_pos(ctx, pos, item)
        {ctx, placed} = pop_changed(ctx, item)
        {:ok, result(ctx), {:placed, pos, placed}}
    end
  end

  def item_guid_at(%Player{} = player, pos, get_item) do
    guid_at(ctx(player, nil, nil, nil, get_item), pos)
  end

  def find_position(%Player{} = player, guid, get_item) do
    ctx = ctx(player, nil, nil, nil, get_item)

    direct = Enum.map(0..(@slot_count - 1), fn slot -> {@bag_0, slot} end)

    Enum.find(direct ++ storage_positions(ctx), fn pos ->
      guid_at(ctx, pos) == guid
    end)
  end

  def reduce_stack(%Player{} = player, pos, count, get_item) do
    ctx = ctx(player, nil, nil, nil, get_item)

    with {:ok, item} <- fetch_item(ctx, pos),
         true <- count > 0 and count < stack_count(item) do
      ctx = mark_changed(ctx, add_stack(item, -count))
      {:ok, result(ctx)}
    else
      _ -> {:error, :item_not_found, guid_at(ctx, pos) || 0, 0}
    end
  end

  def can_store?(%Player{} = player, %ItemTemplate{} = template, count, get_item) do
    ctx = ctx(player, nil, nil, nil, get_item)
    free_position(ctx) != nil or stack_room(ctx, template) >= count
  end

  def split(%Player{} = player, owner_guid, src_pos, dst_pos, %Item{} = new_item, get_item) do
    ctx = ctx(player, nil, nil, owner_guid, get_item)
    count = new_item.item.stack_count

    with {:ok, src_item} <- fetch_item(ctx, src_pos),
         :ok <- validate_split(ctx, src_item, dst_pos, count) do
      ctx = mark_changed(ctx, add_stack(src_item, -count))
      ctx = put_pos(ctx, dst_pos, new_item)
      {ctx, placed} = pop_changed(ctx, new_item)
      {:ok, result(ctx), placed}
    else
      {:error, error} -> {:error, error, guid_at(ctx, src_pos) || 0, 0}
    end
  end

  def destroy(%Player{} = player, pos, get_item) do
    ctx = ctx(player, nil, nil, nil, get_item)

    with {:ok, item} <- fetch_item(ctx, pos),
         :ok <- validate_destructible(ctx, item) do
      {:ok, ctx |> put_pos(pos, nil) |> result(), item}
    else
      {:error, error} -> {:error, error, guid_at(ctx, pos) || 0, 0}
    end
  end

  def detach(%Player{} = player, pos, get_item) do
    ctx = ctx(player, nil, nil, nil, get_item)

    with {:ok, item} <- fetch_item(ctx, pos),
         :ok <- validate_bag_empty_if_bag(ctx, item) do
      {:ok, ctx |> put_pos(pos, nil) |> result(), item}
    else
      {:error, error} -> {:error, error, guid_at(ctx, pos) || 0, 0}
    end
  end

  def free_position(%Player{} = player, get_item) do
    free_position(ctx(player, nil, nil, nil, get_item))
  end

  def find_equip_slot(%Player{} = player, %Unit{} = unit, %Proficiency{} = prof, %Item{} = item, get_item) do
    ctx = ctx(player, unit, prof, nil, get_item)
    template = Item.template(item)

    with :ok <- can_use(unit, prof, template) do
      case candidate_slots(template, unit.class, prof) do
        [] ->
          {:error, :item_cant_be_equipped}

        candidates ->
          {:ok, free_candidate_slot(ctx, candidates) || hd(candidates)}
      end
    end
  end

  defp free_candidate_slot(ctx, candidates) do
    Enum.find(candidates, fn slot ->
      guid_at(ctx, {@bag_0, slot}) == nil and not blocked_offhand?(ctx, slot)
    end)
  end

  def can_use(%Unit{} = unit, %Proficiency{} = prof, %ItemTemplate{} = template) do
    cond do
      (template.allowable_class &&& 1 <<< (unit.class - 1)) == 0 -> {:error, :you_can_never_use_that_item}
      (template.allowable_race &&& 1 <<< (unit.race - 1)) == 0 -> {:error, :you_can_never_use_that_item}
      is_integer(template.required_level) and unit.level < template.required_level -> {:error, :cant_equip_level_i}
      true -> Proficiency.can_equip?(prof, template)
    end
  end

  defp ctx(player, unit, prof, owner_guid, get_item) do
    %{player: player, unit: unit, prof: prof, owner: owner_guid, get_item: get_item, changed: %{}, destroyed: []}
  end

  defp result(ctx) do
    %{player: ctx.player, items: Map.values(ctx.changed), destroyed: ctx.destroyed}
  end

  defp pop_changed(ctx, %Item{object: %Object{guid: guid}} = item) do
    placed = Map.get(ctx.changed, guid, item)
    {%{ctx | changed: Map.delete(ctx.changed, guid)}, placed}
  end

  defp do_swap(ctx, src_pos, dst_pos) do
    with {:ok, src_item} <- fetch_item(ctx, src_pos),
         {:ok, _dst} <- valid_destination(ctx, dst_pos),
         dst_item = item_at(ctx, dst_pos),
         :ok <- validate_bag_cycle(ctx, src_item, dst_pos),
         :ok <- validate_placement(ctx, src_item, dst_pos),
         :ok <- validate_placement(ctx, dst_item, src_pos),
         :ok <- validate_two_hand(ctx, src_item, src_pos, dst_pos, dst_item) do
      if mergeable?(src_item, dst_item) do
        merge_stacks(ctx, src_pos, src_item, dst_item)
      else
        ctx =
          ctx
          |> put_pos(src_pos, dst_item)
          |> put_pos(dst_pos, src_item)
          |> store_offhand_if_two_hand(src_item, dst_pos)

        {:ok, result(ctx)}
      end
    else
      {:error, error} -> {:error, error, guid_at(ctx, src_pos) || 0, guid_at(ctx, dst_pos) || 0}
    end
  end

  defp mergeable?(%Item{} = src_item, %Item{} = dst_item) do
    src_item.object.entry == dst_item.object.entry and
      max_stack(dst_item) > 1 and
      stack_count(dst_item) < max_stack(dst_item)
  end

  defp mergeable?(_src_item, _dst_item), do: false

  defp merge_stacks(ctx, src_pos, src_item, dst_item) do
    space = max_stack(dst_item) - stack_count(dst_item)
    moved = min(space, stack_count(src_item))
    ctx = mark_changed(ctx, add_stack(dst_item, moved))

    ctx =
      if moved == stack_count(src_item) do
        ctx = put_pos(ctx, src_pos, nil)
        %{ctx | changed: Map.delete(ctx.changed, src_item.object.guid), destroyed: [src_item | ctx.destroyed]}
      else
        mark_changed(ctx, add_stack(src_item, -moved))
      end

    {:ok, result(ctx)}
  end

  defp merge_into_stacks(ctx, %Item{} = item) do
    max_stack = max_stack(item)
    entry = item.object.entry
    incoming_guid = item.object.guid

    if max_stack > 1 do
      Enum.reduce_while(storage_positions(ctx), {ctx, stack_count(item)}, fn pos, {ctx, remaining} ->
        case item_at(ctx, pos) do
          %Item{object: %Object{entry: ^entry, guid: guid}} = stack when guid != incoming_guid ->
            space = max_stack - stack_count(stack)
            moved = min(max(space, 0), remaining)
            ctx = if moved > 0, do: mark_changed(ctx, add_stack(stack, moved)), else: ctx
            remaining = remaining - moved
            # credo:disable-for-next-line Credo.Check.Refactor.Nesting
            if remaining == 0, do: {:halt, {ctx, 0}}, else: {:cont, {ctx, remaining}}

          _ ->
            {:cont, {ctx, remaining}}
        end
      end)
    else
      {ctx, stack_count(item)}
    end
  end

  defp stack_room(ctx, %ItemTemplate{entry: entry} = template) do
    max_stack = max(template.stackable, 1)

    storage_positions(ctx)
    |> Enum.map(fn pos ->
      case item_at(ctx, pos) do
        %Item{object: %Object{entry: ^entry}} = stack -> max(max_stack - stack_count(stack), 0)
        _ -> 0
      end
    end)
    |> Enum.sum()
  end

  defp storage_positions(ctx) do
    backpack = Enum.map(@backpack_slot_start..(@slot_count - 1), fn slot -> {@bag_0, slot} end)

    bags =
      Enum.flat_map(@bag_slots, fn bag_slot ->
        case item_at(ctx, {@bag_0, bag_slot}) do
          %Item{container: %Container{}} = bag ->
            # credo:disable-for-next-line Credo.Check.Refactor.Nesting
            Enum.map(0..(container_size(bag.container) - 1)//1, fn slot -> {bag_slot, slot} end)

          _ ->
            []
        end
      end)

    backpack ++ bags
  end

  defp validate_split(ctx, %Item{} = src_item, dst_pos, count) do
    cond do
      count <= 0 or count >= stack_count(src_item) -> {:error, :tried_to_split_more_than_count}
      not match?({:ok, _}, valid_destination(ctx, dst_pos)) -> {:error, :couldnt_split_items}
      equipment_pos?(dst_pos) or bag_bar_pos?(dst_pos) -> {:error, :couldnt_split_items}
      guid_at(ctx, dst_pos) != nil -> {:error, :couldnt_split_items}
      true -> :ok
    end
  end

  defp equipment_pos?({@bag_0, slot}), do: equipment_slot?(slot)
  defp equipment_pos?(_pos), do: false

  defp bag_bar_pos?({@bag_0, slot}), do: bag_slot?(slot)
  defp bag_bar_pos?(_pos), do: false

  defp stack_count(%Item{item: %{stack_count: count}}) when is_integer(count) and count > 0, do: count
  defp stack_count(%Item{}), do: 1

  defp max_stack(%Item{} = item) do
    case Item.template(item).stackable do
      n when is_integer(n) and n > 1 -> n
      _ -> 1
    end
  end

  defp add_stack(%Item{} = item, delta) do
    put_stack_count(item, stack_count(item) + delta)
  end

  defp put_stack_count(%Item{} = item, count) do
    %{item | item: %{item.item | stack_count: count}}
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp candidate_slots(%ItemTemplate{inventory_type: inventory_type} = template, class, prof) do
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
      13 -> if prof.dual_wield?, do: [@mainhand_slot, @offhand_slot], else: [@mainhand_slot]
      17 -> [@mainhand_slot]
      21 -> [@mainhand_slot]
      14 -> [@offhand_slot]
      22 -> [@offhand_slot]
      23 -> [@offhand_slot]
      15 -> [slot_index(:ranged)]
      25 -> [slot_index(:ranged)]
      26 -> [slot_index(:ranged)]
      18 -> @bag_slots
      19 -> [slot_index(:tabard)]
      28 -> relic_slots(template, class)
      _ -> []
    end
  end

  defp blocked_offhand?(ctx, slot) do
    slot == @offhand_slot and two_hand_used?(ctx)
  end

  defp two_hand_used?(ctx) do
    case item_at(ctx, {@bag_0, @mainhand_slot}) do
      %Item{} = item -> Item.template(item).inventory_type == @invtype_two_hand
      _ -> false
    end
  end

  defp relic_slots(%ItemTemplate{subclass: subclass}, class) do
    if Map.get(@relic_subclass_classes, subclass) == class do
      [slot_index(:ranged)]
    else
      []
    end
  end

  defp validate_bag_cycle(ctx, %Item{object: %Object{guid: guid}}, {dst_bag, _slot}) when dst_bag != @bag_0 do
    case item_at(ctx, {@bag_0, dst_bag}) do
      %Item{object: %Object{guid: ^guid}} -> {:error, :items_cant_be_swapped}
      _ -> :ok
    end
  end

  defp validate_bag_cycle(_ctx, _item, _dst_pos), do: :ok

  defp validate_equipment_placement(ctx, template, slot) do
    with :ok <- can_use(ctx.unit, ctx.prof, template) do
      cond do
        offhand_weapon_without_dual_wield?(ctx, template, slot) -> {:error, :cant_dual_wield}
        slot not in candidate_slots(template, ctx.unit.class, ctx.prof) -> {:error, :item_doesnt_go_to_slot}
        slot == @offhand_slot and two_hand_used?(ctx) -> {:error, :cant_equip_with_twohanded}
        true -> :ok
      end
    end
  end

  defp offhand_weapon_without_dual_wield?(ctx, template, slot) do
    slot == @offhand_slot and template.inventory_type == @invtype_one_hand and not ctx.prof.dual_wield?
  end

  defp validate_placement(_ctx, nil, _pos), do: :ok

  defp validate_placement(ctx, %Item{} = item, {@bag_0, slot}) do
    template = Item.template(item)

    cond do
      equipment_slot?(slot) ->
        validate_equipment_placement(ctx, template, slot)

      bag_slot?(slot) ->
        if template.inventory_type == @invtype_bag, do: :ok, else: {:error, :not_a_bag}

      backpack_slot?(slot) ->
        validate_bag_empty_if_bag(ctx, item)

      true ->
        {:error, :item_doesnt_go_to_slot}
    end
  end

  defp validate_placement(ctx, %Item{} = item, {_bag, _slot}) do
    if Item.container?(item) and not bag_empty?(ctx, item) do
      {:error, :nonempty_bag_over_other_bag}
    else
      :ok
    end
  end

  defp validate_bag_empty_if_bag(ctx, %Item{} = item) do
    if Item.container?(item) and not bag_empty?(ctx, item) do
      {:error, :can_only_do_with_empty_bags}
    else
      :ok
    end
  end

  defp bag_empty?(ctx, %Item{object: %Object{guid: guid}} = bag) do
    bag = Map.get(ctx.changed, guid, bag)
    bag_slot_guids(bag) == []
  end

  defp bag_slot_guids(%Item{container: container}) when not is_nil(container) do
    1..container_size(container)
    |> Enum.map(fn i -> Map.get(container, :"slot_#{i}") end)
    |> Enum.filter(fn guid -> is_integer(guid) and guid > 0 end)
  end

  defp bag_slot_guids(_item), do: []

  defp container_size(container) do
    case container.num_slots do
      n when is_integer(n) and n > 0 -> min(n, 36)
      _ -> 0
    end
  end

  defp validate_two_hand(ctx, %Item{} = src_item, src_pos, dst_pos, dst_item) do
    if equipping_two_hand?(src_item, dst_pos) and guid_at(ctx, {@bag_0, @offhand_slot}) != nil and
         not offhand_storable?(ctx, src_pos, dst_item) do
      {:error, :cant_equip_with_twohanded}
    else
      :ok
    end
  end

  defp store_offhand_if_two_hand(ctx, %Item{} = src_item, dst_pos) do
    with true <- equipping_two_hand?(src_item, dst_pos),
         %Item{} = offhand_item <- item_at(ctx, {@bag_0, @offhand_slot}),
         pos when pos != nil <- free_position(ctx) do
      ctx
      |> put_pos({@bag_0, @offhand_slot}, nil)
      |> put_pos(pos, offhand_item)
    else
      _ -> ctx
    end
  end

  defp equipping_two_hand?(%Item{} = item, {@bag_0, @mainhand_slot}) do
    Item.template(item).inventory_type == @invtype_two_hand
  end

  defp equipping_two_hand?(_item, _dst_pos), do: false

  defp offhand_storable?(ctx, src_pos, dst_item) do
    free_position(ctx) != nil or (dst_item == nil and storage_pos?(src_pos))
  end

  defp storage_pos?({@bag_0, slot}), do: backpack_slot?(slot)
  defp storage_pos?({_bag, _slot}), do: true

  defp free_position(ctx) do
    backpack =
      Enum.find_value(@backpack_slot_start..(@slot_count - 1), fn slot ->
        if guid_at(ctx, {@bag_0, slot}) == nil, do: {@bag_0, slot}
      end)

    backpack || free_bag_position(ctx)
  end

  defp free_bag_position(ctx) do
    Enum.find_value(@bag_slots, fn bag_slot ->
      case item_at(ctx, {@bag_0, bag_slot}) do
        %Item{container: %Container{}} = bag ->
          Enum.find_value(0..(container_size(bag.container) - 1)//1, fn slot ->
            # credo:disable-for-next-line Credo.Check.Refactor.Nesting
            if guid_at(ctx, {bag_slot, slot}) == nil, do: {bag_slot, slot}
          end)

        _ ->
          nil
      end
    end)
  end

  defp validate_destructible(ctx, %Item{} = item) do
    cond do
      (Item.template(item).flags &&& @item_flag_indestructible) != 0 -> {:error, :cant_drop_soulbound}
      Item.container?(item) and not bag_empty?(ctx, item) -> {:error, :can_only_do_with_empty_bags}
      true -> :ok
    end
  end

  defp fetch_item(ctx, pos) do
    with {:ok, _} <- valid_destination(ctx, pos),
         %Item{} = item <- item_at(ctx, pos) do
      {:ok, item}
    else
      _ -> {:error, :item_not_found}
    end
  end

  defp valid_destination(_ctx, {@bag_0, slot}) when is_integer(slot) and slot >= 0 and slot < @slot_count do
    {:ok, {@bag_0, slot}}
  end

  defp valid_destination(ctx, {bag, slot} = pos) when is_integer(bag) and is_integer(slot) do
    with true <- bag_slot?(bag),
         %Item{container: %Container{}} = bag_item <- item_at(ctx, {@bag_0, bag}),
         true <- slot >= 0 and slot < container_size(bag_item.container) do
      {:ok, pos}
    else
      _ -> {:error, :item_doesnt_go_to_slot}
    end
  end

  defp valid_destination(_ctx, _pos), do: {:error, :item_doesnt_go_to_slot}

  defp guid_at(ctx, {@bag_0, slot}) do
    with field when is_atom(field) <- Map.get(@field_by_slot, slot),
         guid when is_integer(guid) and guid > 0 <- Map.get(ctx.player, field) do
      guid
    else
      _ -> nil
    end
  end

  defp guid_at(ctx, {bag, slot}) do
    with %Item{container: %Container{}} = bag_item <- item_at(ctx, {@bag_0, bag}),
         true <- slot >= 0 and slot < container_size(bag_item.container),
         guid when is_integer(guid) and guid > 0 <- Map.get(bag_item.container, :"slot_#{slot + 1}") do
      guid
    else
      _ -> nil
    end
  end

  defp item_at(ctx, pos) do
    case guid_at(ctx, pos) do
      guid when is_integer(guid) -> get_item(ctx, guid)
      _ -> nil
    end
  end

  defp get_item(ctx, guid) do
    Map.get(ctx.changed, guid) || ctx.get_item.(guid)
  end

  defp put_pos(ctx, {@bag_0, slot}, item) do
    field = Map.fetch!(@field_by_slot, slot)

    player =
      ctx.player
      |> Map.put(field, item_guid_or_zero(item))
      |> put_visible_entry(slot, item)

    ctx = %{ctx | player: player}
    set_contained(ctx, item, ctx.owner)
  end

  defp put_pos(ctx, {bag, slot}, item) do
    %Item{} = bag_item = item_at(ctx, {@bag_0, bag})
    container = Map.put(bag_item.container, :"slot_#{slot + 1}", item_guid_or_zero(item))
    ctx = mark_changed(ctx, %{bag_item | container: container})
    set_contained(ctx, item, bag_item.object.guid)
  end

  defp set_contained(ctx, nil, _contained), do: ctx

  defp set_contained(ctx, %Item{} = item, contained) do
    item = get_item(ctx, item.object.guid) || item

    if item.item.contained == contained do
      ctx
    else
      mark_changed(ctx, %{item | item: %{item.item | contained: contained}})
    end
  end

  defp mark_changed(ctx, %Item{} = item) do
    %{ctx | changed: Map.put(ctx.changed, item.object.guid, item)}
  end

  defp item_guid_or_zero(nil), do: 0
  defp item_guid_or_zero(%Item{object: %Object{guid: guid}}), do: guid

  def sync_visible_item(%Player{} = player, slot, item) do
    if equipment_slot?(slot) do
      value = if item, do: Item.visible_value(item), else: 0
      Map.put(player, visible_entry_field(slot), value)
    else
      player
    end
  end

  defp put_visible_entry(player, slot, item), do: sync_visible_item(player, slot, item)
end
