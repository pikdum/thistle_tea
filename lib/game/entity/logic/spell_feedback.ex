defmodule ThistleTea.Game.Entity.Logic.SpellFeedback do
  @moduledoc """
  Applies the resolved outcome of an entity's outgoing spell to proc auras
  owned by that entity.
  """

  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell

  def receive(entity, payload, %Spell{} = spell, now) when is_integer(now) do
    event = if payload.outcome == :cast_end, do: :spell_cast_completed, else: :spell_hit_dealt
    {entity, events} = Aura.reactions(entity, event, Map.merge(payload, %{spell: spell, now: now}))
    Effects.enqueue(entity, events)
  end

  def receive(entity, _payload, _spell, _now), do: entity
end
