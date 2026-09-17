defmodule ThistleTea.Game.Entity.Logic.SpellFeedback do
  @moduledoc """
  Applies the resolved outcome of an entity's outgoing spell to proc auras
  owned by that entity.
  """

  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.PlayerCombat
  alias ThistleTea.Game.Spell

  def receive(entity, payload, %Spell{} = spell, now) when is_integer(now) do
    entity = refresh_combat(entity, payload, now)
    {entity, events} = Aura.reactions(entity, :spell_hit_dealt, Map.merge(payload, %{spell: spell, now: now}))
    Effects.enqueue(entity, events)
  end

  def receive(entity, _payload, _spell, _now), do: entity

  defp refresh_combat(entity, %{victim_guid: guid, proc_type: type}, now)
       when type in [:deal_harmful_spell, :deal_harmful_periodic, :deal_ranged_ability] do
    PlayerCombat.mark_hostile_contact(entity, guid, now)
  end

  defp refresh_combat(entity, _payload, _now), do: entity
end
