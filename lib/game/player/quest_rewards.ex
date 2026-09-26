defmodule ThistleTea.Game.Player.QuestRewards do
  @moduledoc "Dispatches a committed quest's reward spell through the appropriate entity owner."

  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  def cast_spell(%{character: character} = state, %Quest{} = quest, giver_guid) do
    case SpellLoader.cached(Quest.reward_spell_id(quest)) do
      %Spell{} = spell ->
        source = caster_guid(spell, giver_guid, character.object.guid)
        event = Effects.trigger_spell_request(source, spell.id, character.object.guid, [])
        %{state | character: EventSink.emit(character, event)}

      _missing ->
        state
    end
  end

  defp caster_guid(%Spell{effects: effects}, giver_guid, player_guid) do
    if Guid.entity_type(giver_guid) == :mob and Enum.any?(effects, &giver_cast?/1),
      do: giver_guid,
      else: player_guid
  end

  defp giver_cast?(effect) do
    effect.type in [:learn_spell, :create_item] or effect.implicit_target_a in [:any_unit, :target_ally]
  end
end
