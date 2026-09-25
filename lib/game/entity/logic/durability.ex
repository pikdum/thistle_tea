defmodule ThistleTea.Game.Entity.Logic.Durability do
  @moduledoc """
  Pure equipment wear and repair planning. Durability and repair payments
  commit together through the inventory transaction boundary.
  """

  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Inventory.Batch
  alias ThistleTea.Game.Spell

  def on_damage(%{object: %{guid: guid}} = entity, previous_health, remaining, new_health, opts)
      when previous_health > 0 and remaining > 0 do
    source = Keyword.get(opts, :source)
    environmental? = Keyword.get(opts, :environmental?, false)
    applicable? = new_health == 0 or (not environmental? and is_integer(source) and source > 0 and source != guid)

    if not applicable? or (new_health == 0 and not death_loss?(opts)) do
      entity
    else
      Effects.enqueue(entity, %Effects.DurabilityDamage{
        source_guid: source,
        lethal?: new_health == 0,
        environmental?: environmental?
      })
    end
  end

  def on_damage(entity, _previous_health, _remaining, _new_health, _opts), do: entity

  defp death_loss?(opts) do
    Keyword.get(opts, :death_durability_loss?, true) and
      not no_death_loss?(Keyword.get(opts, :spell), Keyword.get(opts, :spell_id))
  end

  defp no_death_loss?(_spell, 27_965), do: true
  defp no_death_loss?(%Spell{} = spell, _id), do: Spell.attribute?(spell, :no_durability_loss)
  defp no_death_loss?(_spell, _id), do: false

  def lose(%Item{item: component} = item, :percent, amount)
      when is_number(amount) and amount > 0 and is_integer(component.max_durability) and component.max_durability > 0 do
    lose(item, :points, max(trunc(component.max_durability * amount / 100), 1))
  end

  def lose(%Item{item: component} = item, :points, amount)
      when is_number(amount) and is_integer(component.max_durability) and component.max_durability > 0 do
    durability = component.durability |> Kernel.-(trunc(amount)) |> max(0) |> min(component.max_durability)
    %{item | item: %{component | durability: durability}}
  end

  def lose(%Item{} = item, _mode, _amount), do: item

  def spell_scope(-1), do: :equipped
  def spell_scope(slot) when is_integer(slot) and slot < -1, do: :carried

  def spell_scope(slot) when is_integer(slot) do
    if Inventory.equipment_slot?(slot) or Inventory.bag_slot?(slot), do: {:slot, slot}
  end

  def spell_scope(_slot), do: nil

  def spell_log_entry(%Player{}, scope, _get_item) when scope in [:equipped, :carried], do: -1

  def spell_log_entry(%Player{} = player, scope, get_item) do
    case selected_items(player, scope, get_item) do
      [%Item{object: %{entry: entry}}] -> entry
      _missing -> nil
    end
  end

  def loss(%Player{} = player, mode, amount, scope, get_item) do
    player
    |> selected_items(scope, get_item)
    |> Enum.reduce(Batch.new(player), fn item, batch ->
      case lose(item, mode, amount) do
        ^item -> batch
        changed -> Batch.update(batch, changed)
      end
    end)
    |> Inventory.plan(get_item)
  end

  def repair(%Player{} = player, item_guid, get_item, get_price) do
    items = Inventory.owned_items(player, get_item)
    items = if item_guid == 0, do: items, else: Enum.filter(items, &(&1.object.guid == item_guid))

    with {:ok, prices} <- prices(items, get_price),
         total = Enum.sum(Enum.map(prices, &elem(&1, 1))),
         true <- (player.coinage || 0) >= total do
      prices
      |> Enum.reduce(Batch.new(%{player | coinage: (player.coinage || 0) - total}), fn {item, _cost}, batch ->
        Batch.update(batch, %{item | item: %{item.item | durability: item.item.max_durability}})
      end)
      |> Inventory.plan(get_item)
    else
      false -> {:error, :not_enough_money}
      error -> error
    end
  end

  def repair_cost(%Item{item: component}, multiplier, quality, discount \\ 1.0)
      when is_number(multiplier) and is_number(quality) and is_number(discount) do
    lost = max((component.max_durability || 0) - (component.durability || 0), 0)

    if lost > 0 do
      lost
      |> Kernel.*(multiplier * quality)
      |> round()
      |> Kernel.*(client_float(discount))
      |> client_float()
      |> round_discount()
      |> max(1)
    else
      0
    end
  end

  defp round_discount(value) do
    whole = trunc(value)
    if value - whole == 0.5, do: whole + rem(whole, 2), else: round(value)
  end

  defp client_float(value) do
    <<result::float-size(32)>> = <<value::float-size(32)>>
    result
  end

  def cost_key(%ItemTemplate{item_level: level, quality: quality, class: class, subclass: subclass})
      when class in [2, 4] do
    {level, class, subclass, (quality + 1) * 2}
  end

  def cost_key(%ItemTemplate{}), do: nil

  defp selected_items(player, :carried, get_item), do: Inventory.owned_items(player, get_item)

  defp selected_items(player, :equipped, get_item) do
    for slot <- Inventory.slots(), %Item{} = item <- [get_item.(Map.get(player, slot))], do: item
  end

  defp selected_items(player, slot, get_item) when is_atom(slot) do
    if slot in Inventory.slots(), do: Enum.filter([get_item.(Map.get(player, slot))], &is_struct(&1, Item)), else: []
  end

  defp selected_items(player, {:slot, slot}, get_item) do
    with {:slot, ^slot} <- spell_scope(slot),
         field = Inventory.field_for_position({255, slot}),
         guid = player |> Map.from_struct() |> Map.fetch!(field),
         %Item{} = item <- get_item.(guid) do
      [item]
    else
      _missing -> []
    end
  end

  defp prices(items, get_price) do
    items
    |> Enum.filter(&damaged?/1)
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, prices} ->
      case get_price.(item) do
        cost when is_integer(cost) and cost > 0 -> {:cont, {:ok, [{item, cost} | prices]}}
        _missing -> {:halt, {:error, :missing_repair_cost}}
      end
    end)
  end

  defp damaged?(%Item{item: component}) do
    is_integer(component.max_durability) and component.max_durability > 0 and
      component.durability < component.max_durability
  end
end
