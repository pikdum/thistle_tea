defmodule ThistleTea.Game.World.Loader.SpellAppearance do
  @moduledoc "Compiles spell appearance choices and creature equipment into pure model data."

  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.DBC
  alias ThistleTea.Game.Entity.Data.CreatureTemplate
  alias ThistleTea.Game.Entity.Data.Model
  alias ThistleTea.Game.Entity.Logic.Appearance
  alias ThistleTea.Game.World.Loader.CreatureTemplate, as: CreatureTemplateLoader
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.ModelGeometry

  @deception_models %{
    1 => {10_137, 10_138},
    2 => {10_139, 10_140},
    3 => {10_141, 10_142},
    4 => {10_143, 10_144},
    5 => {10_146, 10_145},
    6 => {10_136, 10_147},
    7 => {10_148, 10_149},
    8 => {10_135, 10_134}
  }

  def load(:transform, 0, 16_739), do: deception_models()
  def load(:transform, entry, _spell_id), do: creature_model(entry)

  def load(:mod_shapeshift, form, _spell_id) do
    Map.new([{:default, 0}, {6, 6}], fn {key, race} ->
      model =
        case Appearance.shapeshift_model(form, race) do
          %Model{} = shape -> %{ModelGeometry.get(shape.display_id) | scale: shape.scale}
          nil -> nil
        end

      {key, model}
    end)
  end

  def load(_aura, _value, _spell_id), do: nil

  def creature_model(entry) do
    case CreatureTemplateLoader.get(entry) do
      %CreatureTemplate{} = template ->
        template_model(template)

      _missing ->
        nil
    end
  end

  defp template_model(%CreatureTemplate{display_ids: displays, display_scales: scales, equipment_id: equipment_id}) do
    case Enum.find_index(displays, &(is_integer(&1) and &1 > 0)) do
      nil ->
        nil

      index ->
        model = ModelGeometry.get(Enum.at(displays, index))
        scale = Enum.at(scales || [], index)
        scale = if is_number(scale) and scale > 0, do: scale, else: model.scale
        %{model | scale: scale, equipment: equipment(equipment_id)}
    end
  end

  defp deception_models do
    DBC.all(ChrRaces)
    |> Enum.filter(&Map.has_key?(@deception_models, &1.id))
    |> Enum.flat_map(fn race ->
      {male, female} = Map.fetch!(@deception_models, race.id)

      for {gender, display, native} <- [{0, male, race.male_display}, {1, female, race.female_display}] do
        model = ModelGeometry.get(display)
        native_scale = ModelGeometry.get(native).scale
        scale = deception_scale(race.id, gender, native_scale)
        {{race.id, gender}, %{model | scale: scale}}
      end
    end)
    |> Map.new()
  end

  defp deception_scale(6, _gender, native), do: 1.15 / native
  defp deception_scale(7, 0, native), do: 1.35 / native
  defp deception_scale(7, 1, native), do: 1.25 / native
  defp deception_scale(_race, _gender, _native), do: 1.0

  defp equipment(id) when is_integer(id) and id > 0 do
    case Mangos.Repo.one(from(row in Mangos.CreatureEquipTemplate, where: row.entry == ^id, limit: 1)) do
      nil -> [nil, nil, nil]
      row -> Enum.map([row.item1, row.item2, row.item3], &ItemLoader.get_template/1)
    end
  end

  defp equipment(_id), do: [nil, nil, nil]
end
