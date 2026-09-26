defmodule ThistleTea.Game.Entity.Logic.Aura.ProcSpell do
  @moduledoc """
  Resolves proc spells whose target, strength, or chance depends on the
  triggering spell outcome, before normal triggered-spell delivery.
  """

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell

  @blessed_recovery %{27_811 => 27_813, 27_815 => 27_817, 27_816 => 27_818}
  @mana_drain 27_522
  @mana_drain_energize 29_471
  @mana_drain_leech 27_526
  @persistent_shield 26_467
  @persistent_shield_absorb 26_470
  @pyroclasm %{18_096 => 13, 18_073 => 26}
  @pyroclasm_stun 18_093
  @shadowguard %{
    18_137 => 28_377,
    19_308 => 28_378,
    19_309 => 28_379,
    19_310 => 28_380,
    19_311 => 28_381,
    19_312 => 28_382
  }

  def resolve(event, holder, context, roll \\ &:rand.uniform/0)

  def resolve(%Effects.TriggerSpell{} = event, %Holder{spell: %Spell{id: @mana_drain}}, _context, _roll) do
    [
      %{event | spell_id: @mana_drain_energize, target_guid: event.source_guid, requires_living_target?: true},
      %{event | spell_id: @mana_drain_leech, requires_living_target?: true}
    ]
  end

  def resolve(%Effects.TriggerSpell{} = event, %Holder{spell: %Spell{id: id}}, _context, _roll)
      when is_map_key(@shadowguard, id) do
    [%{event | spell_id: Map.fetch!(@shadowguard, id), requires_living_target?: true}]
  end

  def resolve(%Effects.TriggerSpell{} = event, %Holder{spell: %Spell{id: id}}, context, roll)
      when is_map_key(@pyroclasm, id) do
    with %{victim_alive?: true, spell: %Spell{} = spell} <- context,
         true <- event.source_guid != event.target_guid,
         ticks when is_integer(ticks) <- pyroclasm_ticks(spell),
         true <- roll.() * 100 <= Map.fetch!(@pyroclasm, id) / ticks do
      [%{event | spell_id: @pyroclasm_stun, requires_living_target?: true}]
    else
      _ineligible -> []
    end
  end

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

  defp pyroclasm_ticks(%Spell{spell_family: 5, spell_icon: 184, spell_visual: 2253}), do: 1

  defp pyroclasm_ticks(%Spell{} = spell) do
    cond do
      Spell.family_flag?(spell, 5, 0x40) -> 15
      Spell.family_flag?(spell, 5, 0x20) -> 4
      true -> nil
    end
  end

  defp custom_spell(%Effects.TriggerSpell{} = event, spell_id, target_guid, amount) do
    %{event | spell_id: spell_id, target_guid: target_guid, slot: 0, amount: amount, requires_living_target?: true}
  end
end
