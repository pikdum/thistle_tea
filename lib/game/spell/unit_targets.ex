defmodule ThistleTea.Game.Spell.UnitTargets do
  @moduledoc "Creature selectors and per-effect unit recipients retained for spell delivery."

  import Bitwise, only: [&&&: 2, <<<: 2]

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target

  defstruct by_effect: %{}, error: nil

  defmodule Selector do
    @moduledoc false
    defstruct [:entry, :condition, alive?: true, inverse_effect_mask: 0]
  end

  def required?(%Spell{effects: effects}), do: Enum.any?(effects, &scripted?/1)

  def scripted?(%Effect{} = effect), do: :creature_near_caster in [effect.implicit_target_a, effect.implicit_target_b]

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

  def item_selection(targets, %__MODULE__{} = units, item_guid) when is_integer(item_guid) do
    case guids(units) do
      [guid | _] -> %{targets | selection: {:unit, guid}}
      [] -> targets
    end
  end

  def item_selection(%Target{} = targets, _units, _item_guid), do: targets

  def corpse_effect?(spell, effect, %{object: %{entry: entry}}) do
    scripted?(effect) and Enum.any?(selectors(spell, effect), &(&1.entry == entry and not &1.alive?))
  end
end
