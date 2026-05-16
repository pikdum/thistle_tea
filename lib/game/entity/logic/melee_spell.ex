defmodule ThistleTea.Game.Entity.Logic.MeleeSpell do
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Spell

  def queue_next_swing(%{internal: %Internal{} = internal} = entity, %Spell{} = spell) do
    %{entity | internal: %{internal | next_swing_spell: spell}}
  end

  def queue_next_swing(entity, _spell), do: entity

  def consume_next_swing(%{internal: %Internal{next_swing_spell: %Spell{} = spell} = internal} = entity) do
    {%{entity | internal: %{internal | next_swing_spell: nil}}, spell}
  end

  def consume_next_swing(entity), do: {entity, nil}
end
