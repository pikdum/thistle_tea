defmodule ThistleTea.Game.Entity.Logic.Trade do
  @moduledoc """
  Pure trade negotiation and two-sided inventory planning. Neither side changes
  unless both complete plans succeed against the supplied inventory snapshot.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.Trade
  alias ThistleTea.Game.Entity.Data.Trade.Exchange
  alias ThistleTea.Game.Entity.Data.Trade.Offer
  alias ThistleTea.Game.Entity.Logic.Enchantments
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Inventory.Batch
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet

  @max_money 2_147_483_647
  @accept_delay_ms 200

  def new(id, initiator, recipient, now) when initiator != recipient do
    %Trade{
      id: id,
      initiator: initiator,
      recipient: recipient,
      modified_at: now,
      offers: %{initiator => %Offer{}, recipient => %Offer{}}
    }
  end

  def participants(%Trade{} = trade), do: [trade.initiator, trade.recipient]
  def other(%Trade{initiator: guid, recipient: other}, guid), do: other
  def other(%Trade{recipient: guid, initiator: other}, guid), do: other
  def other(_trade, _guid), do: nil

  def open(%Trade{phase: :requested, recipient: guid} = trade, guid), do: {:ok, %{trade | phase: :open}}
  def open(_trade, _guid), do: {:error, :trade_canceled}

  def money(%Trade{phase: :open} = trade, guid, amount, now) when is_integer(amount) and amount in 0..@max_money do
    update_offer(trade, guid, now, &%{&1 | money: amount})
  end

  def money(_trade, _guid, _amount, _now), do: {:error, :trade_canceled}

  def put_item(%Trade{phase: :open} = trade, guid, slot, %Item{} = item, now) when slot in 0..6 do
    with %Offer{} = offer <- Map.get(trade.offers, guid),
         false <- Enum.any?(offer.items, fn {_slot, other} -> other.object.guid == item.object.guid end) do
      update_offer(trade, guid, now, &%{&1 | items: Map.put(&1.items, slot, item)})
    else
      _ -> {:error, :trade_canceled}
    end
  end

  def put_item(_trade, _guid, _slot, _item, _now), do: {:error, :trade_canceled}

  def clear_item(%Trade{phase: :open} = trade, guid, slot, now) when slot in 0..6 do
    update_offer(trade, guid, now, &%{&1 | items: Map.delete(&1.items, slot)})
  end

  def clear_item(_trade, _guid, _slot, _now), do: {:error, :trade_canceled}

  def unaccept(%Trade{phase: :open} = trade, guid) do
    case Map.get(trade.offers, guid) do
      %Offer{} = offer -> {:ok, %{trade | offers: Map.put(trade.offers, guid, %{offer | accepted?: false})}}
      _ -> {:error, :trade_canceled}
    end
  end

  def unaccept(_trade, _guid), do: {:error, :trade_canceled}

  def accept(%Trade{phase: :open} = trade, guid, now) do
    with true <- now - trade.modified_at >= @accept_delay_ms,
         %Offer{} = offer <- Map.get(trade.offers, guid) do
      offers = Map.put(trade.offers, guid, %{offer | accepted?: true})
      phase = if Enum.all?(offers, fn {_guid, offer} -> offer.accepted? end), do: :preparing, else: :open
      {:ok, %{trade | offers: offers, phase: phase}}
    else
      _ -> {:error, :back_to_trade}
    end
  end

  def accept(_trade, _guid, _now), do: {:error, :trade_canceled}

  def reopen(%Trade{} = trade), do: %{trade | phase: :open, offers: clear_acceptance(trade.offers)}

  def validate_item(%Character{} = character, %Item{} = item, slot, now, get_item, get_enchantment) when slot in 0..6 do
    position = Inventory.find_position(character.player, item.object.guid, get_item)

    cond do
      item.item.owner != character.object.guid -> {:error, :dont_own_that_item}
      is_nil(position) -> {:error, :item_not_found}
      slot == 6 -> :ok
      Enchantments.bound?(item, now, get_enchantment) -> {:error, :cant_drop_soulbound}
      equipped_bag?(position) -> {:error, :cant_trade_equip_bags}
      nonempty_bag?(item) -> {:error, :can_only_do_with_empty_bags}
      equipped_in_combat?(character, position) -> {:error, :not_in_combat}
      true -> :ok
    end
  end

  def validate_item(_character, _item, _slot, _now, _get_item, _get_enchantment), do: {:error, :item_not_found}

  def plan(%Trade{phase: :preparing} = trade, characters, now, get_item, get_enchantment) do
    with :ok <- validate_offers(trade, characters, now, get_item, get_enchantment),
         {:ok, first} <- plan_side(trade, trade.initiator, characters, get_item),
         {:ok, second} <- plan_side(trade, trade.recipient, characters, get_item) do
      outgoing = Map.new(trade.offers, fn {guid, offer} -> {guid, Enum.map(traded_items(offer), & &1.object.guid)} end)

      {:ok,
       %Exchange{id: trade.id, changes: %{trade.initiator => first, trade.recipient => second}, outgoing: outgoing}}
    end
  end

  defp update_offer(trade, guid, now, update) do
    case Map.get(trade.offers, guid) do
      %Offer{} = offer ->
        offers = trade.offers |> Map.put(guid, update.(offer)) |> clear_acceptance()
        {:ok, %{trade | offers: offers, modified_at: now}}

      _ ->
        {:error, :trade_canceled}
    end
  end

  defp clear_acceptance(offers), do: Map.new(offers, fn {guid, offer} -> {guid, %{offer | accepted?: false}} end)

  defp validate_offers(trade, characters, now, get_item, get_enchantment) do
    Enum.reduce_while(trade.offers, :ok, fn {guid, offer}, :ok ->
      character = Map.fetch!(characters, guid)

      result = validate_offer(offer, character, now, get_item, get_enchantment)

      if result == :ok, do: {:cont, :ok}, else: {:halt, error_for(guid, result)}
    end)
  end

  defp validate_offer(offer, character, now, get_item, get_enchantment) do
    Enum.reduce_while(offer.items, :ok, fn {slot, item}, :ok ->
      result =
        if get_item.(item.object.guid) == item,
          do: validate_item(character, item, slot, now, get_item, get_enchantment),
          else: {:error, :item_not_found}

      if result == :ok, do: {:cont, :ok}, else: {:halt, result}
    end)
  end

  defp plan_side(trade, guid, characters, get_item) do
    character = Map.fetch!(characters, guid)
    own = Map.fetch!(trade.offers, guid)
    other = Map.fetch!(trade.offers, other(trade, guid))
    money = character.player.coinage - own.money + other.money

    cond do
      own.money > character.player.coinage -> {:error, guid, :not_enough_money}
      money > @max_money -> {:error, guid, :too_much_gold}
      true -> plan_inventory(character, own, other, money, get_item)
    end
  end

  defp plan_inventory(character, own, other, money, get_item) do
    batch = Batch.new(%{character.player | coinage: money})
    batch = Enum.reduce(traded_items(own), batch, &Batch.relocate(&2, &1.object.guid, :detached))

    batch =
      Enum.reduce(traded_items(other), batch, fn item, batch ->
        received = %{item | item: %{item.item | owner: character.object.guid, contained: character.object.guid}}
        Batch.add(batch, received)
      end)

    case Inventory.plan(batch, get_item) do
      {:ok, changes} ->
        merged = for %{status: :merged, incoming_guid: guid} <- changes.placements, do: get_item.(guid)
        {:ok, ChangeSet.absorb(changes, %{player: changes.player, items: [], destroyed: merged})}

      error ->
        error_for(character.object.guid, error)
    end
  end

  defp traded_items(%Offer{items: items}) do
    items |> Enum.sort() |> Enum.flat_map(fn {slot, item} -> if slot < 6, do: [item], else: [] end)
  end

  defp error_for(guid, {:error, reason}), do: {:error, guid, reason}
  defp equipped_bag?({255, slot}), do: Inventory.bag_slot?(slot)
  defp equipped_bag?(_position), do: false
  defp equipped_in_combat?(%Character{internal: %{in_combat: true}}, {255, slot}), do: slot < 15 or slot == 18
  defp equipped_in_combat?(_character, _position), do: false
  defp nonempty_bag?(%Item{container: nil}), do: false

  defp nonempty_bag?(%Item{container: container}) do
    Enum.any?(1..36, fn slot ->
      value = Map.fetch!(container, :"slot_#{slot}")
      is_integer(value) and value > 0
    end)
  end
end
