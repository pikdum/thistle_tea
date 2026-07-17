defmodule ThistleTea.Game.Entity.Logic.Druid do
  @moduledoc """
  Druid spell scripts that VMangos also implements outside DBC mechanics.
  """

  import Bitwise, only: [&&&: 2, |||: 2]

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Spell

  @druid_family 7
  @rejuvenation_mask 0x10
  @regrowth_mask 0x40
  @enrage_armor_spell 25_503

  def ferocious_bite?(%Spell{} = spell) do
    Spell.vmangos_script?(spell, "spell_druid_ferocious_bite")
  end

  def ferocious_bite_bonus(%Spell{} = spell, attack_power, combo_points, energy, damage_multiplier) do
    if ferocious_bite?(spell) do
      trunc(
        max(attack_power || 0, 0) * max(combo_points || 0, 0) * 0.03 +
          max(energy || 0, 0) * max(damage_multiplier || 0, 0)
      )
    else
      0
    end
  end

  def enrage_event(%{object: %{guid: guid}, unit: %{level: level, shapeshift_form: form}}, %Spell{} = spell)
      when is_integer(guid) and is_integer(level) do
    if Spell.vmangos_script?(spell, "spell_druid_enrage") do
      reduction = if form == 8, do: -16, else: -27
      Event.trigger_spell(guid, level, guid, @enrage_armor_spell, effect_index: 1, base_points: reduction)
    end
  end

  def enrage_event(_entity, _spell), do: nil

  def consume_swiftmend_hot(entity, %Spell{} = spell, now) do
    if Spell.vmangos_script?(spell, "spell_druid_swiftmend") do
      do_consume_swiftmend_hot(entity, now)
    else
      {entity, 0, []}
    end
  end

  def consume_swiftmend_hot(entity, _spell, _now), do: {entity, 0, []}

  defp do_consume_swiftmend_hot(entity, now) do
    case swiftmend_holder(entity) do
      %Holder{spell: hot, auras: auras} ->
        tick_heal =
          Enum.find_value(auras, 0, fn
            %Aura{type: :periodic_heal, amount: amount} when is_integer(amount) -> amount
            _aura -> nil
          end)

        multiplier = if ((hot.family_flags_0 || 0) &&& @regrowth_mask) == 0, do: 4, else: 6
        {entity, events} = AuraLogic.remove_spells(entity, [hot.id], now)
        {entity, tick_heal * multiplier, events}

      nil ->
        {entity, 0, []}
    end
  end

  defp swiftmend_holder(%{unit: %{auras: holders}}) when is_list(holders) do
    holders
    |> Enum.filter(&swiftmend_hot?/1)
    |> Enum.min_by(&remaining_duration/1, fn -> nil end)
  end

  defp swiftmend_holder(_entity), do: nil

  defp swiftmend_hot?(%Holder{spell: %Spell{spell_family: @druid_family, family_flags_0: flags}, auras: auras})
       when is_integer(flags) do
    (flags &&& (@rejuvenation_mask ||| @regrowth_mask)) != 0 and
      Enum.any?(auras, &match?(%Aura{type: :periodic_heal}, &1))
  end

  defp swiftmend_hot?(_holder), do: false

  defp remaining_duration(%Holder{expires_at: expires_at}) when is_integer(expires_at), do: expires_at
  defp remaining_duration(_holder), do: 9_223_372_036_854_775_807
end
