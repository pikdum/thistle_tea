defmodule ThistleTea.Game.Battleground.Resurrection do
  @moduledoc "The waiting aura is the player's authority to accept a battleground resurrection wave."

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell

  @waiting_spell 2584

  def spell_id, do: @waiting_spell

  def waiting?(%Character{unit: %{auras: holders}}), do: Enum.any?(holders || [], &(&1.spell.id == @waiting_spell))

  def ready?(%Character{} = character), do: not Death.alive?(character) and waiting?(character)

  def after_remove(%Character{} = character, %Holder{spell: %Spell{id: @waiting_spell}}) do
    if waiting?(character),
      do: [],
      else: [%Effects.CancelBattlegroundResurrection{world: character.internal.world, guid: character.object.guid}]
  end

  def after_remove(_entity, _holder), do: []
end
