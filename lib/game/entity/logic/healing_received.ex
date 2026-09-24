defmodule ThistleTea.Game.Entity.Logic.HealingReceived do
  @moduledoc """
  Applies current healing-received bonuses when healing lands, including
  each HoT tick. School-specific flat bonuses use the spell coefficient and
  cannot reduce healing by more than half. The strongest percentage reduction
  and increase combine multiplicatively after flat bonuses.
  """
  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Paladin
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Coefficient
  alias ThistleTea.Game.Spell.Effect

  def amount(entity, amount) when is_number(amount) do
    {reduction, increase} = extremes(entity)
    max(trunc(amount * max(100 + reduction, 0) / 100 * (100 + increase) / 100), 0)
  end

  def heal(entity, amount) do
    if Core.dead?(entity), do: entity, else: Core.heal(entity, amount(entity, amount))
  end

  def spell_amount(entity, amount, spell, effect, opts \\ [])

  def spell_amount(entity, amount, %Spell{dmg_class: class} = spell, %Effect{} = effect, opts)
      when class in [1, 2, 3] do
    amount = max(amount, 0)

    benefit =
      AuraLogic.flat_modifier(entity, :mod_healing, Spell.school_mask(spell)) +
        Paladin.blessing_of_light_bonus(entity, spell)

    coefficient = Coefficient.value(spell, effect, Keyword.get(opts, :damage_type, :direct))
    stacks = max(Keyword.get(opts, :stacks, 1), 1)
    multiplier = Keyword.get(opts, :coefficient_multiplier, 1.0)
    flat = max(benefit * coefficient * stacks * multiplier, -amount / 2)
    amount(entity, (amount + flat) * healing_way_multiplier(entity, spell))
  end

  def spell_amount(entity, amount, _spell, _effect, _opts), do: amount(entity, amount)

  defp healing_way_multiplier(%{unit: %Unit{auras: holders}}, %Spell{} = spell) when is_list(holders) do
    if Spell.family_flag?(spell, 11, 0x40) do
      for %Holder{spell: %Spell{id: 29_203}, auras: auras, stacks: stacks} <- holders,
          %Aura{type: :dummy, amount: amount} <- auras,
          is_number(amount),
          reduce: 1.0 do
        multiplier -> multiplier * max(100 + amount * max(stacks || 1, 1), 0) / 100
      end
    else
      1.0
    end
  end

  defp healing_way_multiplier(_entity, _spell), do: 1.0

  defp extremes(%{unit: %Unit{auras: holders}}) when is_list(holders) do
    Enum.reduce(holders, {0, 0}, fn %Holder{auras: auras, stacks: stacks}, limits ->
      Enum.reduce(auras, limits, fn
        %Aura{type: :mod_healing_pct, amount: amount}, {low, high} when is_number(amount) ->
          value = amount * max(stacks || 1, 1)
          {min(low, value), max(high, value)}

        _aura, limits ->
          limits
      end)
    end)
  end

  defp extremes(_entity), do: {0, 0}
end
