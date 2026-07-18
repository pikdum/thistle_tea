defmodule ThistleTea.Game.Entity.Logic.SpellFeedback do
  @moduledoc """
  Applies the resolved outcome of an entity's outgoing spell to proc auras
  owned by that entity.
  """

  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Spell

  def receive(entity, payload, %Spell{} = spell, now) when is_integer(now) do
    {entity, events} = Aura.reactions(entity, :spell_hit_dealt, Map.merge(payload, %{spell: spell, now: now}))
    Event.enqueue(entity, events)
  end

  def receive(entity, _payload, _spell, _now), do: entity
end
