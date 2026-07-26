defmodule ThistleTea.Game.Spell.Critical.Modifier do
  @moduledoc false

  @enforce_keys [:condition, :amount]
  defstruct [:condition, :amount]
end

defmodule ThistleTea.Game.Spell.Critical do
  @moduledoc """
  Snapshots caster-side conditional critical-strike modifiers and resolves
  their target-side conditions at spell impact.
  """
  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Critical.Modifier

  @shatter_amounts %{
    849 => 10,
    910 => 20,
    911 => 30,
    912 => 40,
    913 => 50
  }

  def snapshot(%{unit: %Unit{auras: holders}}, %Spell{spell_family: family}) when is_list(holders) do
    for %Holder{spell: %Spell{spell_family: ^family}, auras: auras} <- holders,
        %Aura{type: :override_class_scripts, misc_value: script} <- auras,
        amount = Map.get(@shatter_amounts, script),
        is_integer(amount),
        do: %Modifier{condition: :target_frozen, amount: amount}
  end

  def snapshot(_caster, _spell), do: []

  def target_bonus(modifiers, target) when is_list(modifiers) do
    Enum.reduce(modifiers, 0, fn
      %Modifier{condition: :target_frozen, amount: amount}, bonus when is_integer(amount) ->
        if AuraLogic.frozen?(target), do: bonus + amount, else: bonus

      _modifier, bonus ->
        bonus
    end)
  end

  def target_bonus(_modifiers, _target), do: 0
end
