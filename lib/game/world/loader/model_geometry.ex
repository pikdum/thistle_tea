defmodule ThistleTea.Game.World.Loader.ModelGeometry do
  @moduledoc """
  Boot-loaded display scales and model geometry, with dimensions normalized to
  object scale one. Gameplay boundaries read ETS without querying source tables.
  """
  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.DBC
  alias ThistleTea.Game.Entity.Data.Model

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
    Enum.each(rows, fn row ->
      model = %Model{display_id: row.id, height: normalized_height(row), scale: native_scale(row)}
      :ets.insert(table, {row.id, model})
    end)
  end

  def height(display_id, table \\ __MODULE__) do
    get(display_id, table).height
  end

  def get(display_id, table \\ __MODULE__) do
    case :ets.lookup(table, display_id) do
      [{^display_id, %Model{} = model}] -> model
      [] -> %Model{display_id: display_id}
    end
  end

  def load_all_addons do
    from(row in Mangos.CreatureDisplayInfoAddon, order_by: [asc: row.display_id, desc: row.build])
    |> Mangos.Repo.all()
    |> Enum.uniq_by(& &1.display_id)
    |> load_addons()
  end

  def load_addons(rows, table \\ __MODULE__) do
    Enum.each(rows, fn row ->
      model = get(row.display_id, table)

      model = %{
        model
        | bounding_radius: normalize(row.bounding_radius, model.scale, model.bounding_radius),
          combat_reach: normalize(row.combat_reach, model.scale, model.combat_reach)
      }

      :ets.insert(table, {row.display_id, model})
    end)
  end

  defp native_scale(%{model_scale: model, display_scale: display}), do: positive(model, 1.0) * positive(display, 1.0)

  defp positive(value, _default) when is_number(value) and value > 0, do: value
  defp positive(_value, default), do: default

  defp normalize(value, scale, _default) when is_number(value) and value > 0, do: value / scale
  defp normalize(_value, _scale, default), do: default

  defp normalized_height(%{collision_height: height, model_scale: model, display_scale: scale})
       when is_number(height) and height > 0 and is_number(model) and model > 0 and is_number(scale) and scale > 0 do
    height / model / (model * scale)
  end

  defp normalized_height(_row), do: 2.0
end
