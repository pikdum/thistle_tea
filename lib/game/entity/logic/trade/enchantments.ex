defmodule ThistleTea.Game.Entity.Logic.Trade.Enchantments do
  @moduledoc """
  Validates queued trade enchants and folds their costs and target changes into
  the two inventory plans. Offered items cannot also pay an enchantment's cost.
  """
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemEnchantment
  alias ThistleTea.Game.Entity.Data.Trade.Enchantment
  alias ThistleTea.Game.Entity.Data.Trade.Offer
  alias ThistleTea.Game.Entity.Logic.Enchantments
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Inventory.Batch
  alias ThistleTea.Game.Entity.Logic.ItemUse
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastValidation
  alias ThistleTea.Game.Spell.Target

  def validate(_character, %Offer{spell: nil}, _target, _now, _get_item, _get_enchantment), do: :ok

  def validate(character, %Offer{spell: %Enchantment{} = cast}, %Item{} = item, now, get_item, get_enchantment) do
    with :ok <- validate_spell(character, cast, item, get_enchantment) do
      CastValidation.validate(character, cast.spell, %Target{selection: {:trade_item, 6}}, nil, now,
        count_item: &Inventory.count_entry(character.player, &1, get_item),
        enchant_item: item,
        enchant_ownership: :trade
      )
    end
  end

  def validate(_character, _offer, _item, _now, _get_item, _get_enchantment), do: {:error, :item_gone}

  def costs(batch, _character, %Offer{spell: nil}, _get_item), do: {:ok, batch}

  def costs(batch, character, %Offer{spell: %Enchantment{} = cast, items: offered}, get_item) do
    excluded = MapSet.new(offered, fn {_slot, item} -> item.object.guid end)
    reagents = if character.internal.godmode, do: [], else: cast.spell.reagents

    available =
      Enum.reject(Inventory.owned_items(character.player, get_item), &MapSet.member?(excluded, &1.object.guid))

    with {:ok, batch} <- reagent_costs(batch, available, reagents),
         {:ok, batch} <- cast_item_cost(batch, character, cast, excluded, get_item) do
      skilled =
        if cast.cast_item_guid, do: character, else: Enchantments.skill_up(character, cast.recipe, cast.skill_roll)

      {:ok, %{batch | player: %{batch.player | skills: skilled.player.skills}}}
    end
  end

  def target_change(batch, _own, %Offer{spell: nil}, _get_item, _now), do: batch

  def target_change(batch, own, %Offer{spell: %Enchantment{} = cast}, get_item, now) do
    item = Map.fetch!(own.items, 6)
    item = Enum.reduce(cast.effects, item, &apply_enchantment(&2, &1, now))
    position = Inventory.find_position(batch.player, item.object.guid, get_item)

    player =
      case position do
        {255, slot} -> Inventory.sync_visible_item(batch.player, slot, item)
        _ -> batch.player
      end

    Batch.update(%{batch | player: player}, item)
  end

  defp validate_spell(character, cast, item, get_enchantment) do
    cond do
      not is_nil(character.internal.casting) ->
        {:error, :spell_in_progress}

      item.object.guid != cast.target_guid ->
        {:error, :item_gone}

      not Enchantments.item_enchant?(cast.spell) ->
        {:error, :bad_targets}

      Spell.attribute?(cast.spell, :enchant_own_item_only) ->
        {:error, :not_tradeable}

      not known_or_item_cast?(character, cast) ->
        {:error, :not_known}

      not Enum.all?(cast.effects, &tradeable_enchantment?(&1, get_enchantment)) ->
        {:error, :not_tradeable}

      true ->
        :ok
    end
  end

  defp known_or_item_cast?(character, cast) do
    not is_nil(cast.cast_item_guid) or Map.has_key?(character.internal.spellbook || %{}, cast.spell.id)
  end

  defp tradeable_enchantment?(%{id: id}, get_enchantment) do
    case get_enchantment.(id) do
      %ItemEnchantment{flags: flags} -> ((flags || 0) &&& 1) == 0
      _ -> false
    end
  end

  defp reagent_costs(batch, available, reagents) do
    reagents
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.sort()
    |> Enum.reduce_while({:ok, batch}, fn {entry, counts}, {:ok, batch} ->
      {batch, remaining} = take_reagent(batch, available, entry, Enum.sum(counts))
      if remaining == 0, do: {:cont, {:ok, batch}}, else: {:halt, {:error, :reagents}}
    end)
  end

  defp take_reagent(batch, available, entry, count) do
    Enum.reduce(available, {batch, count}, fn item, {batch, remaining} ->
      if item.object.entry == entry and remaining > 0 do
        used = min(item.item.stack_count, remaining)
        {Batch.remove_item(batch, item.object.guid, used), remaining - used}
      else
        {batch, remaining}
      end
    end)
  end

  defp cast_item_cost(batch, _character, %Enchantment{cast_item_guid: nil}, _excluded, _get_item), do: {:ok, batch}

  defp cast_item_cost(batch, character, %Enchantment{cast_item_guid: guid, spell: spell}, excluded, get_item) do
    with false <- MapSet.member?(excluded, guid),
         {_bag, _slot} <- Inventory.find_position(character.player, guid, get_item),
         %Item{item: %{owner: owner}} = item when owner == character.object.guid <- get_item.(guid),
         template = Item.template(item),
         index when is_integer(index) <-
           Enum.find(
             1..5,
             &(Map.fetch!(template, :"spellid_#{&1}") == spell.id and Map.fetch!(template, :"spelltrigger_#{&1}") == 0)
           ) do
      ItemUse.plan(batch, item, index)
    else
      _ -> {:error, :item_gone}
    end
  end

  defp apply_enchantment(item, %{type: :enchant_item, id: id}, _now), do: Item.put_permanent_enchantment(item, id)

  defp apply_enchantment(
         item,
         %{type: :enchant_item_temporary, id: id, duration_ms: duration, charges: charges, token: token},
         now
       ) do
    Item.put_temporary_enchantment(item, id, duration, charges, now + duration, token)
  end
end
