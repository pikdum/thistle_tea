defmodule ThistleTea.Game.Entity.Logic.Trade do
  @moduledoc """
  Pure trade negotiation and two-sided inventory planning. Neither side changes
  unless both complete plans succeed against the supplied inventory snapshot.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.Trade
  alias ThistleTea.Game.Entity.Data.Trade.Enchantment
  alias ThistleTea.Game.Entity.Data.Trade.Exchange
  alias ThistleTea.Game.Entity.Data.Trade.Offer
  alias ThistleTea.Game.Entity.Logic.Enchantments
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Inventory.Batch
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet
  alias ThistleTea.Game.Entity.Logic.Trade.Enchantments, as: TradeEnchantments
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.Target

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

  def enchant(%Trade{phase: :open} = trade, guid, %Enchantment{} = cast, now) do
    case target_item(trade, guid) do
      %Item{object: %{guid: target}} when target == cast.target_guid ->
        update_offer(trade, guid, now, &%{&1 | spell: cast})

      _ ->
        {:error, :trade_canceled}
    end
  end

  def enchant(_trade, _guid, _cast, _now), do: {:error, :trade_canceled}

  def target_item(%Trade{} = trade, guid) do
    case Map.get(trade.offers, other(trade, guid)) do
      %Offer{} = offer -> Map.get(offer.items, 6)
      _ -> nil
    end
  end

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
      Item.loot_generated?(item) -> {:error, :item_locked}
      casting_uses?(character, item) -> {:error, :item_locked}
      true -> validate_slot(character, item, position, slot, now, get_enchantment)
    end
  end

  def validate_item(_character, _item, _slot, _now, _get_item, _get_enchantment), do: {:error, :item_not_found}

  defp validate_slot(_character, _item, _position, 6, _now, _get_enchantment), do: :ok

  defp validate_slot(character, item, position, _slot, now, get_enchantment) do
    cond do
      Enchantments.bound?(item, now, get_enchantment) -> {:error, :cant_drop_soulbound}
      equipped_bag?(position) -> {:error, :cant_trade_equip_bags}
      nonempty_bag?(item) -> {:error, :can_only_do_with_empty_bags}
      equipped_in_combat?(character, position) -> {:error, :not_in_combat}
      true -> :ok
    end
  end

  def plan(%Trade{phase: :preparing} = trade, characters, now, get_item, get_enchantment) do
    with :ok <- validate_offers(trade, characters, now, get_item, get_enchantment),
         :ok <- validate_enchantments(trade, characters, now, get_item, get_enchantment),
         {:ok, first} <- plan_side(trade, trade.initiator, characters, get_item, now),
         {:ok, second} <- plan_side(trade, trade.recipient, characters, get_item, now) do
      outgoing = Map.new(trade.offers, fn {guid, offer} -> {guid, Enum.map(traded_items(offer), & &1.object.guid)} end)

      {:ok,
       %Exchange{
         id: trade.id,
         changes: %{trade.initiator => first, trade.recipient => second},
         outgoing: outgoing,
         casts: Map.new(trade.offers, fn {guid, offer} -> {guid, offer.spell} end),
         committed_at: now
       }}
    end
  end

  defp update_offer(trade, guid, now, update) do
    case Map.get(trade.offers, guid) do
      %Offer{} = offer ->
        offers = trade.offers |> Map.put(guid, update.(offer)) |> clear_acceptance()
        {:ok, clear_invalid_enchantments(%{trade | offers: offers, modified_at: now})}

      _ ->
        {:error, :trade_canceled}
    end
  end

  defp clear_acceptance(offers), do: Map.new(offers, fn {guid, offer} -> {guid, %{offer | accepted?: false}} end)

  defp clear_invalid_enchantments(trade) do
    offers =
      Map.new(trade.offers, fn
        {guid, %Offer{spell: %Enchantment{target_guid: target}} = offer} ->
          case target_item(trade, guid) do
            %Item{object: %{guid: ^target}} -> {guid, offer}
            _ -> {guid, %{offer | spell: nil}}
          end

        pair ->
          pair
      end)

    %{trade | offers: offers}
  end

  defp validate_enchantments(trade, characters, now, get_item, get_enchantment) do
    Enum.reduce_while(trade.offers, :ok, fn {guid, offer}, :ok ->
      case TradeEnchantments.validate(
             Map.fetch!(characters, guid),
             offer,
             target_item(trade, guid),
             now,
             get_item,
             get_enchantment
           ) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, guid, {:cast, offer.spell.spell.id, reason}}}
      end
    end)
  end

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

  defp plan_side(trade, guid, characters, get_item, now) do
    character = Map.fetch!(characters, guid)
    own = Map.fetch!(trade.offers, guid)
    other = Map.fetch!(trade.offers, other(trade, guid))
    money = character.player.coinage - own.money + other.money

    cond do
      own.money > character.player.coinage -> {:error, guid, :not_enough_money}
      money > @max_money -> {:error, guid, :too_much_gold}
      true -> plan_inventory(character, own, other, money, get_item, now)
    end
  end

  defp plan_inventory(character, own, other, money, get_item, now) do
    batch = Batch.new(%{character.player | coinage: money})
    batch = Enum.reduce(traded_items(own), batch, &Batch.relocate(&2, &1.object.guid, :detached))

    batch =
      Enum.reduce(traded_items(other), batch, fn item, batch ->
        received = %{item | item: %{item.item | owner: character.object.guid, contained: character.object.guid}}
        Batch.add(batch, received)
      end)

    with {:ok, batch} <- TradeEnchantments.costs(batch, character, own, get_item),
         batch = TradeEnchantments.target_change(batch, own, other, get_item, now),
         {:ok, changes} <- Inventory.plan(batch, get_item) do
      merged = for %{status: :merged, incoming_guid: guid} <- changes.placements, do: get_item.(guid)
      {:ok, ChangeSet.absorb(changes, %{player: changes.player, items: [], destroyed: merged})}
    else
      {:error, reason} when reason in [:reagents, :item_gone, :no_charges_remain] ->
        {:error, character.object.guid, {:cast, own.spell.spell.id, reason}}

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

  defp casting_uses?(%Character{internal: %{casting: %Cast{} = cast}}, item) do
    target =
      case cast.targets do
        %Target{} = targets -> Target.item_guid(targets)
        _ -> nil
      end

    item.object.guid in [cast.cast_item_guid, target] or
      Enum.any?(cast.spell.reagents, fn {entry, _count} -> entry == item.object.entry end)
  end

  defp casting_uses?(_character, _item), do: false
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
