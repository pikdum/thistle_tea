defmodule ThistleTea.Game.World.Loader.ModelGeometry do
  @moduledoc """
  Boot-loaded model collision heights per display, normalized to object scale
  one. Gameplay boundaries read ETS without querying DBC tables.
  """
  import Ecto.Query

  alias ThistleTea.DBC

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, [:named_table, :public, read_concurrency: true])
      _ -> table
    end
  end

  def load_all do
    from(display in CreatureDisplayInfo,
      join: model in CreatureModelData,
      on: model.id == display.model,
      select: %{
        id: display.id,
        display_scale: display.creature_model_scale,
        model_scale: model.model_scale,
        collision_height: model.collision_height
      }
    )
    |> DBC.all()
    |> load()
  end

  def load(rows, table \\ __MODULE__) do
    Enum.each(rows, &:ets.insert(table, {&1.id, normalized_height(&1)}))
  end

  def height(display_id, table \\ __MODULE__) do
    case :ets.lookup(table, display_id) do
      [{^display_id, height}] -> height
      [] -> 2.0
    end
  end

  defp normalized_height(%{collision_height: height, model_scale: model, display_scale: scale})
       when is_number(height) and height > 0 and is_number(model) and model > 0 and is_number(scale) and scale > 0 do
    height / model / (model * scale)
  end

  defp normalized_height(_row), do: 2.0
end
