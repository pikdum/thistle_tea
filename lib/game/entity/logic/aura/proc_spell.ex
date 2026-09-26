defmodule ThistleTea.Game.Entity.Logic.Aura.ProcSpell do
  @moduledoc """
  Resolves proc spells whose target and strength depend on the triggering
  damage or healing, before normal triggered-spell delivery.
  """

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell

  @blessed_recovery %{27_811 => 27_813, 27_815 => 27_817, 27_816 => 27_818}
  @persistent_shield 26_467
  @persistent_shield_absorb 26_470

  def resolve(event, holder, context, roll \\ &:rand.uniform/0)

  def resolve(%Effects.TriggerSpell{} = event, %Holder{spell: %Spell{id: id}} = holder, context, roll)
      when is_map_key(@blessed_recovery, id) do
    with %{damage: damage} when is_integer(damage) and damage > 0 <- context,
         %Aura{amount: percent} when is_integer(percent) and percent > 0 <-
           Enum.find(holder.auras, &(&1.type == :proc_trigger_spell)) do
      amount = trunc(damage * percent / 300 + roll.())
      [custom_spell(event, Map.fetch!(@blessed_recovery, id), event.source_guid, amount)]
    else
      _missing_amount -> []
    end
  end

  def resolve(%Effects.TriggerSpell{} = event, %Holder{spell: %Spell{id: @persistent_shield}}, context, _roll) do
    case context do
      %{damage: healing, victim_alive?: true} when is_integer(healing) and healing > 0 ->
        [custom_spell(event, @persistent_shield_absorb, event.target_guid, div(healing * 15, 100))]

      _missing_heal ->
        []
    end
  end

  def resolve(event, _holder, _context, _roll), do: [event]

  defp custom_spell(%Effects.TriggerSpell{} = event, spell_id, target_guid, amount) do
    %{event | spell_id: spell_id, target_guid: target_guid, slot: 0, amount: amount, requires_living_target?: true}
  end
end
