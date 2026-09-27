defmodule ThistleTea.Game.Entity.Logic.Engineering.DeathRay do
  @moduledoc "Tracks Death Ray's channeled self-damage and releases its accumulated charge on expiry."

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast

  @channel 13_278
  @periodic 13_493
  @discharge 13_279

  def aura_amount(%Spell{} = spell, roll \\ &:rand.uniform/1) do
    if periodic?(spell), do: 99 + roll.(401)
  end

  def application_time(
        %{internal: %{casting: %Cast{spell: %Spell{id: @channel}, phase: :channel_tick} = cast}},
        spell,
        now
      ) do
    if periodic?(spell), do: cast.ends_at - cast.channel_ms, else: now
  end

  def application_time(_entity, _spell, now), do: now

  def periodic_amount(entity, %Spell{} = spell, %Aura{} = aura, amount) do
    if periodic?(spell) do
      amount = if channeling?(entity), do: amount, else: 0
      {%{aura | accumulated_damage: aura.accumulated_damage + trunc(amount)}, amount}
    else
      {aura, amount}
    end
  end

  def after_remove(
        %{object: %{guid: guid}, unit: %{health: health, level: level, target: target}},
        %Holder{} = holder,
        :expired
      )
      when health > 0 and is_integer(target) and target > 0 do
    amount = Enum.sum(Enum.map(holder.auras, & &1.accumulated_damage))

    if periodic?(holder.spell) and amount > 0 do
      [
        Effects.trigger_spell(guid, level || 1, target, @discharge,
          effect_index: 0,
          base_points: amount,
          requires_living_target?: true,
          triggered_by_spell_id: @periodic
        )
      ]
    else
      []
    end
  end

  def after_remove(_entity, _holder, _cause), do: []

  defp periodic?(spell), do: Spell.vmangos_script?(spell, "spell_gdr_periodic")

  defp channeling?(%{internal: %{casting: %Cast{spell: %Spell{id: @channel}, phase: :channel_tick}}}), do: true
  defp channeling?(_entity), do: false
end
