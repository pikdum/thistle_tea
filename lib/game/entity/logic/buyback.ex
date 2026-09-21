defmodule ThistleTea.Game.Entity.Logic.Buyback do
  @moduledoc """
  Pure vendor sale and buyback plans. Carried inventory, money, buyback slots,
  and item identity change together in one inventory change set.
  """
  import Bitwise, only: [<<<: 2, |||: 2]

  alias ThistleTea.Game.Entity.Data.Buyback
  alias ThistleTea.Game.Entity.Data.Buyback.Change
  alias ThistleTea.Game.Entity.Data.Buyback.Entry
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Inventory.Batch
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet
  alias ThistleTea.Game.Entity.Logic.ItemLifetime

  @slots 69..80
  @max_money 2_147_483_647

  def sell(%Character{} = character, guid, count, new_guid, now, get_item, get_penalty) do
    with %Item{} = item <- get_item.(guid),
         :ok <- sellable(character, item, count, now, get_item),
         count = if(count == 0, do: item.item.stack_count, else: count),
         {:ok, price} <- sale_price(item, count, get_penalty),
         true <- (character.player.coinage || 0) + price <= @max_money do
      plan_sale(character, item, count, price, new_guid, now, get_item)
    else
      nil -> {:error, :cant_find_item}
      false -> {:error, :cant_sell_item}
      error -> error
    end
  end

  def restore(%Character{} = character, slot, now, get_item) when slot in @slots do
    buyback = character.internal.buyback

    with %Entry{} = entry <- Map.get(buyback.entries, slot),
         %Item{} = item <- get_item.(entry.guid),
         true <- item.item.owner == character.object.guid,
         :ok <- affordable(character.player, entry.price),
         buyback = remove(buyback, slot),
         player = project(%{character.player | coinage: character.player.coinage - entry.price}, buyback),
         item = resume(item, entry.sold_at, now),
         {:ok, inventory} <- player |> Batch.new() |> Batch.add(item) |> Inventory.plan(get_item) do
      inventory = retire_merged(inventory, item)
      {:ok, %Change{inventory: inventory, buyback: buyback}}
    else
      nil -> {:error, :cant_find_item}
      false -> {:error, :cant_find_item}
      error -> error
    end
  end

  def restore(%Character{}, _slot, _now, _get_item), do: {:error, :cant_find_item}

  def clear(%Character{} = character, now, get_item) do
    destroyed =
      for {_slot, entry} <- character.internal.buyback.entries,
          %Item{} = item <- [get_item.(entry.guid)],
          item.item.owner == character.object.guid,
          do: item

    buyback = %Buyback{started_at: now}
    player = project(character.player, buyback)
    {:ok, inventory} = player |> Batch.new() |> Inventory.plan(get_item)
    inventory = ChangeSet.absorb(inventory, %{player: player, items: [], destroyed: destroyed})
    %Change{inventory: inventory, buyback: buyback}
  end

  def sale_price(%Item{} = item, count, get_penalty) do
    base = Item.template(item).sell_price * count
    price = charged_price(item, base)

    case get_penalty.(item) do
      penalty when is_integer(penalty) and penalty >= 0 ->
        {:ok, if(penalty > price, do: 1, else: price - penalty)}

      _ ->
        {:error, :cant_sell_item}
    end
  end

  def project(%Player{} = player, %Buyback{} = buyback) do
    fields = for slot <- @slots, do: {field(slot), entry_value(buyback, slot, :guid)}

    struct!(
      player,
      fields ++ [buyback_prices: packed(buyback, :price), buyback_timestamps: packed(buyback, :timestamp)]
    )
  end

  defp sellable(character, item, count, now, get_item) do
    cond do
      item.item.owner != character.object.guid ->
        {:error, :you_dont_own_that_item}

      is_nil(Inventory.find_position(character.player, item.object.guid, :carried, get_item)) ->
        {:error, :cant_sell_item}

      not is_integer(count) or count < 0 or count > item.item.stack_count ->
        {:error, :cant_sell_item}

      Item.template(item).sell_price <= 0 ->
        {:error, :cant_sell_item}

      ItemLifetime.expired?(item, now) ->
        {:error, :cant_sell_item}

      true ->
        :ok
    end
  end

  defp plan_sale(character, item, count, price, new_guid, now, get_item) do
    complete? = count == item.item.stack_count
    batch = Batch.new(%{character.player | coinage: (character.player.coinage || 0) + price})

    batch =
      if complete?,
        do: Batch.relocate(batch, item.object.guid, :detached),
        else: Batch.consume_item(batch, item.object.guid, count)

    case Inventory.plan(batch, get_item) do
      {:ok, inventory} ->
        sold = %{
          item
          | object: %{item.object | guid: if(complete?, do: item.object.guid, else: new_guid)},
            item: %{item.item | contained: 0, stack_count: count}
        }

        sold = pause(sold, now)
        {buyback, slot, evicted} = insert(character.internal.buyback, sold.object.guid, price, now, get_item)
        player = project(inventory.player, buyback)
        inventory = ChangeSet.absorb(inventory, %{player: player, items: [], destroyed: evicted})
        inventory = ChangeSet.place(inventory, sold, {:placed, {255, slot}, sold})

        {:ok,
         %Change{
           inventory: inventory,
           buyback: buyback,
           sold_guid: item.object.guid,
           removed_from_inventory?: complete?
         }}

      {:error, :can_only_do_with_empty_bags} ->
        {:error, :only_empty_bag}

      _ ->
        {:error, :cant_sell_item}
    end
  end

  defp insert(buyback, guid, price, now, get_item) do
    started = buyback.started_at || now
    slot = available_slot(buyback)

    evicted =
      case Map.get(buyback.entries, slot) do
        %Entry{guid: guid} -> Enum.filter([get_item.(guid)], &is_struct(&1, Item))
        nil -> []
      end

    entry = %Entry{guid: guid, price: price, sold_at: now, timestamp: max(div(now - started, 1_000), 0) + 108_000}

    buyback = %{
      buyback
      | started_at: started,
        entries: Map.put(buyback.entries, slot, entry),
        next_slot: min(buyback.next_slot + 1, 80)
    }

    {buyback, slot, evicted}
  end

  defp available_slot(%Buyback{entries: entries, next_slot: slot} = buyback) do
    if Map.has_key?(entries, slot) do
      Enum.find(70..80, &(not Map.has_key?(entries, &1))) ||
        Enum.min_by(@slots, &{entry_value(buyback, &1, :timestamp), &1})
    else
      slot
    end
  end

  defp remove(%Buyback{} = buyback, slot) do
    next = if Map.has_key?(buyback.entries, buyback.next_slot), do: slot, else: buyback.next_slot
    %{buyback | entries: Map.delete(buyback.entries, slot), next_slot: next}
  end

  defp pause(item, now) do
    {item, _enchantment} = Item.refresh_temporary_enchantment(item, now)
    ItemLifetime.pause(item, now)
  end

  defp resume(item, sold_at, now) do
    item = ItemLifetime.start(item, now)

    case Item.temporary_enchantment(item) do
      %{id: id, charges: charges, expires_at: expires_at, token: token} ->
        remaining = max(expires_at - sold_at, 0)
        Item.put_temporary_enchantment(item, id, remaining, charges, now + remaining, token)

      nil ->
        item
    end
  end

  defp retire_merged(inventory, item) do
    case ChangeSet.placement(inventory, item.object.guid) do
      %{status: :merged} -> ChangeSet.absorb(inventory, %{player: inventory.player, items: [], destroyed: [item]})
      _ -> inventory
    end
  end

  defp charged_price(item, price) do
    template = Item.template(item)

    spells = [
      {1, template.spellid_1, template.spellcharges_1},
      {2, template.spellid_2, template.spellcharges_2},
      {3, template.spellid_3, template.spellcharges_3},
      {4, template.spellid_4, template.spellcharges_4},
      {5, template.spellid_5, template.spellcharges_5}
    ]

    case Enum.find(spells, fn {_slot, id, charges} -> id != 0 and charges < 0 end) do
      nil -> price
      {slot, _id, charges} -> trunc(client_float(price * client_float(Item.spell_charge(item, slot) / charges)))
    end
  end

  defp client_float(value) do
    <<result::float-size(32)>> = <<value::float-size(32)>>
    result
  end

  defp affordable(player, price), do: if((player.coinage || 0) >= price, do: :ok, else: {:error, :not_enough_money})
  defp field(slot), do: :"buyback#{slot - 68}"

  defp entry_value(buyback, slot, key) do
    entry_value(Map.get(buyback.entries, slot), key)
  end

  defp entry_value(%Entry{guid: guid}, :guid), do: guid
  defp entry_value(%Entry{price: price}, :price), do: price
  defp entry_value(%Entry{timestamp: timestamp}, :timestamp), do: timestamp
  defp entry_value(nil, _key), do: 0

  defp packed(buyback, key), do: Enum.reduce(@slots, 0, &(&2 ||| entry_value(buyback, &1, key) <<< ((&1 - 69) * 32)))
end
