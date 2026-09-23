defmodule ThistleTea.Game.Spell.ObjectTargets do
  @moduledoc "Resolved game-object spell targets, retained by effect index for launch and delivery."

  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  defstruct by_effect: %{}, error: nil

  defmodule Selector do
    @moduledoc false
    defstruct [:entry, :condition, inverse_effect_mask: 0]
  end

  def required?(%Spell{effects: effects}), do: Enum.any?(effects, &(&1.type == :activate_object))

  def validate(%Spell{} = spell, targets) do
    case {required?(spell), targets} do
      {false, _} -> :ok
      {true, %__MODULE__{error: nil}} -> :ok
      {true, %__MODULE__{error: reason}} -> {:error, reason}
      {true, _missing} -> {:error, :bad_targets}
    end
  end

  def guids(%__MODULE__{by_effect: targets}),
    do: targets |> Map.values() |> List.flatten() |> Enum.uniq() |> Enum.sort()

  def guids(_targets), do: []

  def actions(%Spell{} = spell, %__MODULE__{by_effect: targets}) do
    for %Effect{type: :activate_object, index: index, misc_value: action} <- spell.effects,
        guid <- Map.get(targets, index, []) do
      %Effects.SpellGameObjectAction{target_guid: guid, spell_id: spell.id, action: action}
    end
  end

  def actions(_spell, _targets), do: []
end
