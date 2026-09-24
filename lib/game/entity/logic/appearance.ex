defmodule ThistleTea.Game.Entity.Logic.Appearance do
  @moduledoc """
  Projects appearance from native inputs and active holders. Negative transforms
  take priority over positive ones, with the newest application winning within
  each group. Removing a transform reveals the remaining transform, shapeshift,
  or native model without retaining an old display snapshot.
  """

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.Model
  alias ThistleTea.Game.Entity.Logic.ScriptEquipment

  def sync_unit(%Unit{} = unit) do
    case model(unit) do
      %Model{display_id: display} ->
        %{unit | display_id: display}

      nil when is_integer(unit.native_display_id) and unit.native_display_id > 0 ->
        %{unit | display_id: unit.native_display_id}

      nil ->
        unit
    end
  end

  def model(%Unit{} = unit), do: transform(unit) || shapeshift(unit)

  def project(%{object: object, unit: %Unit{} = unit} = entity, multiplier) do
    model = model(unit)
    scale = if model, do: model.scale, else: object.base_scale_x || 1.0
    object = %{object | scale_x: scale * multiplier}
    unit = geometry(unit, model, object.scale_x, multiplier)
    %{entity | object: object, unit: unit}
  end

  def reconcile_equipment(%Mob{} = entity, previous, current) do
    previous_model = transform(%{entity.unit | auras: previous})
    current_model = transform(%{entity.unit | auras: current})

    case {equipment(previous_model), equipment(current_model)} do
      {same, same} -> entity
      {_old, nil} -> ScriptEquipment.reset(entity)
      {_old, items} -> %{entity | unit: ScriptEquipment.apply(entity.unit, items)}
    end
  end

  def reconcile_equipment(entity, _previous, _current), do: entity

  def metadata(%{unit: %Unit{} = unit, object: %Object{} = object}) do
    %{
      display_id: unit.display_id,
      scale_x: object.scale_x,
      bounding_radius: unit.bounding_radius,
      combat_reach: unit.combat_reach
    }
  end

  def metadata(_entity), do: %{}

  def shapeshift_model(1, 6), do: %Model{display_id: 8571, scale: 0.8}
  def shapeshift_model(1, _race), do: %Model{display_id: 892, scale: 0.8}
  def shapeshift_model(3, _race), do: %Model{display_id: 632, scale: 0.8}
  def shapeshift_model(4, _race), do: %Model{display_id: 2428, scale: 0.8}
  def shapeshift_model(form, 6) when form in [5, 8], do: %Model{display_id: 2289}
  def shapeshift_model(form, _race) when form in [5, 8], do: %Model{display_id: 2281}
  def shapeshift_model(16, _race), do: %Model{display_id: 4613, scale: 0.8}
  def shapeshift_model(31, 6), do: %Model{display_id: 15_375}
  def shapeshift_model(31, _race), do: %Model{display_id: 15_374}
  def shapeshift_model(32, _race), do: %Model{display_id: 16_031}
  def shapeshift_model(_form, _race), do: nil

  defp transform(%Unit{auras: holders} = unit) when is_list(holders) do
    holders
    |> Enum.filter(&Holder.has_aura_type?(&1, :transform))
    |> Enum.reverse()
    |> Enum.sort_by(&{&1.negative?, is_integer(&1.applied_at), &1.applied_at}, :desc)
    |> Enum.find_value(&holder_model(&1, unit, :transform))
  end

  defp transform(_unit), do: nil

  defp shapeshift(%Unit{auras: holders, shapeshift_form: form, race: race} = unit) do
    Enum.find_value(holders || [], &holder_model(&1, unit, :mod_shapeshift)) || shapeshift_model(form, race)
  end

  defp holder_model(%Holder{auras: auras}, unit, type) do
    Enum.find_value(auras, fn
      %Aura{type: ^type, appearance: %Model{} = model} ->
        model

      %Aura{type: ^type, appearance: models} when is_map(models) ->
        Map.get(models, {unit.race, unit.gender}) || Map.get(models, unit.race) || Map.get(models, :default)

      %Aura{type: :transform, misc_value: display} when type == :transform and is_integer(display) and display > 0 ->
        %Model{display_id: display}

      _aura ->
        nil
    end)
  end

  defp geometry(%Unit{} = unit, %Model{} = model, scale, _multiplier) do
    %{
      unit
      | bounding_radius: dimension(unit.base_bounding_radius, model.bounding_radius * scale, unit.bounding_radius),
        combat_reach: dimension(unit.base_combat_reach, model.combat_reach * scale, unit.combat_reach)
    }
  end

  defp geometry(%Unit{} = unit, nil, _scale, multiplier) do
    %{
      unit
      | bounding_radius: native_dimension(unit.base_bounding_radius, multiplier, unit.bounding_radius),
        combat_reach: native_dimension(unit.base_combat_reach, multiplier, unit.combat_reach)
    }
  end

  defp dimension(base, value, _current) when is_number(base), do: value
  defp dimension(_base, _value, current), do: current

  defp native_dimension(base, multiplier, _current) when is_number(base), do: base * multiplier
  defp native_dimension(_base, _multiplier, current), do: current

  defp equipment(%Model{equipment: equipment}), do: equipment
  defp equipment(nil), do: nil
end
