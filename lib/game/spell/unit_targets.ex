defmodule ThistleTea.Game.Spell.UnitTargets do
  @moduledoc "Creature selectors and per-effect unit recipients retained for spell delivery."

  import Bitwise, only: [&&&: 2, <<<: 2]

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target

  @area_modes [:script_units_at_source, :script_units_at_destination, :script_units_in_cone]
  @modes [:creature_near_caster | @area_modes]

  defstruct by_effect: %{}, selected_guid: nil, error: nil

  defmodule Selector do
    @moduledoc false
    defstruct [:entry, :condition, alive?: true, inverse_effect_mask: 0]
  end

  def required?(%Spell{effects: effects}), do: Enum.any?(effects, &scripted?/1)

  def scripted?(%Effect{} = effect), do: mode(effect) != nil

  def mode(%Effect{} = effect), do: Enum.find([effect.implicit_target_a, effect.implicit_target_b], &(&1 in @modes))

  def area?(%Spell{effects: effects}), do: Enum.any?(effects, &(mode(&1) in @area_modes))

  def selectors(%Spell{unit_targets: selectors}, %Effect{index: index}),
    do: Enum.filter(selectors, &((&1.inverse_effect_mask &&& 1 <<< index) == 0))

  def validate(%Spell{} = spell, targets) do
    case {required?(spell), targets} do
      {false, _} -> :ok
      {true, %__MODULE__{error: nil}} -> :ok
      {true, %__MODULE__{error: reason}} -> {:error, reason}
      {true, _missing} -> {:error, :bad_targets}
    end
  end

  def guids(%__MODULE__{by_effect: targets}), do: targets |> Enum.sort() |> Enum.flat_map(&elem(&1, 1)) |> Enum.uniq()

  def indices(%__MODULE__{by_effect: targets}, guid),
    do: for({index, guids} <- targets, guid in guids, do: index) |> Enum.sort()

  def indices(nil, _guid), do: nil

  def filter_effects(effects, nil), do: effects
  def filter_effects(effects, indices), do: Enum.filter(effects, &(&1.index in indices))

  def item_selection(targets, %__MODULE__{selected_guid: guid}, item_guid)
      when is_integer(item_guid) and is_integer(guid), do: %{targets | selection: {:unit, guid}}

  def item_selection(%Target{} = targets, _units, _item_guid), do: targets

  def corpse_effect?(spell, effect, %{object: %{entry: entry}}) do
    scripted?(effect) and Enum.any?(selectors(spell, effect), &(&1.entry == entry and not &1.alive?))
  end
end
