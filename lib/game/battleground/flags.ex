defmodule ThistleTea.Game.Battleground.Flags do
  @moduledoc "Connects removal of a player's carrier aura to the owning Warsong flag transition."

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.GameObjectInteraction
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.WorldRef

  def remove(%Character{} = character, now), do: Aura.remove_spells(character, [23_333, 23_335], now)

  def admit(%Character{internal: %{world: %WorldRef{map_id: 489, instance_id: instance_id}}} = character, %Spell{id: id})
      when is_integer(instance_id) and id in [23_333, 23_335] do
    if GameObjectInteraction.battleground_allowed?(character),
      do: :ok,
      else: {:error, removal_effects(character, id)}
  end

  def admit(_entity, _spell), do: :ok

  def after_remove(
        %Character{internal: %{world: %WorldRef{map_id: 489, instance_id: instance_id}}} = character,
        %Holder{spell: %Spell{id: id}}
      )
      when is_integer(instance_id) and id in [23_333, 23_335] do
    removal_effects(character, id)
  end

  def after_remove(_entity, _holder), do: []

  defp removal_effects(character, id) do
    if Aura.has_spell?(character, id) do
      []
    else
      [
        %Effects.BattlegroundFlagRemoved{
          world: character.internal.world,
          guid: character.object.guid,
          team: if(id == 23_333, do: :horde, else: :alliance),
          position: character.movement_block.position
        }
      ]
    end
  end
end
