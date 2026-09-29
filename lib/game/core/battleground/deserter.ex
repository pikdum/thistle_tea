defmodule ThistleTea.Game.Core.Battleground.Deserter do
  @moduledoc "Early battleground departure penalties backed by the ordinary aura lifecycle."

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Battleground.Player
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Spell

  @spell_id 26_013

  def spell_id, do: @spell_id
  def active?(%Character{} = character), do: Aura.has_spell?(character, @spell_id)

  def earned?(%{phase: phase}, %Player{status: :inside}) when phase in [:countdown, :active], do: true
  def earned?(_match, %Player{}), do: false

  def apply(%Character{} = character, %Spell{id: @spell_id} = spell, now) do
    if active?(character),
      do: {character, []},
      else: Aura.apply_spell(character, character.object.guid, character.unit.level, spell, now)
  end
end
