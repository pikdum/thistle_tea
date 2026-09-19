defmodule ThistleTea.Game.Entity.Logic.Durability do
  @moduledoc """
  Pure equipment wear and repair planning. Durability and repair payments
  commit together through the inventory transaction boundary.
  """

  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Inventory.Batch

  def lose(%Item{item: component} = item, mode, amount)
      when is_number(amount) and amount > 0 and is_integer(component.max_durability) and component.max_durability > 0 do
    points = if mode == :percent, do: max(trunc(component.max_durability * amount / 100), 1), else: trunc(amount)
    %{item | item: %{component | durability: max(component.durability - points, 0)}}
  end

  def lose(%Item{} = item, _mode, _amount), do: item

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
    if lost > 0, do: max(round(trunc(lost * multiplier * quality) * discount), 1), else: 0
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
