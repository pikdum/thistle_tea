defmodule ThistleTea.Game.Player.Talents do
  @moduledoc """
  Boundary for spending and resetting talent points: validates the request
  through the pure talent rules, teaches the rank spell, applies any new
  passive auras, and resyncs the unspent-points field on the client.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Entity.Logic.Talents, as: LogicTalents
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Player.Spells
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Loader.SpellPetAura, as: SpellPetAuraLoader
  alias ThistleTea.Game.World.Loader.Talent, as: TalentLoader

  def learn(%{character: %Character{} = character} = state, talent_id, requested_rank) do
    with {:ok, talent_spell_ids} <- LogicTalents.validate(character, talent_id, requested_rank),
         {:ok, character, _events} <- Spells.learn(character, with_dependent_spells(talent_spell_ids)) do
      character = apply_pet_aura_links(character, talent_spell_ids)
      commit(state, character)
    else
      _invalid -> state
    end
  end

  def learn(state, _talent_id, _requested_rank), do: state

  def reset(%{character: %Character{internal: internal} = character} = state) do
    case LogicTalents.known_talent_spell_ids(internal.spells || []) do
      [] ->
        state

      talent_spell_ids ->
        commit(state, Spells.unlearn(character, with_dependent_spells(talent_spell_ids), Time.now()))
    end
  end

  def reset(state), do: state

  def reset_if_overbudget(%{character: %Character{internal: internal}} = state, level) when is_integer(level) do
    if LogicTalents.spent_points(internal.spells || []) > LogicTalents.total_points(level) do
      reset(state)
    else
      state
    end
  end

  def reset_if_overbudget(state, _level), do: state

  defp commit(state, %Character{} = character) do
    character =
      character
      |> Spells.apply_passives(Time.now())
      |> LogicTalents.sync_points()

    CharacterStore.put(character)
    Network.send_packet(Core.update_object(character, :values))
    %{state | character: character}
  end

  defp with_dependent_spells(spell_ids) do
    Enum.flat_map(spell_ids, &[&1 | TalentLoader.dependent_spell_ids(&1)])
  end

  defp apply_pet_aura_links(%Character{} = character, talent_spell_ids) do
    with pet_guid when is_integer(pet_guid) <- Character.controlled_guid(character),
         [_id | _rest] = aura_ids <-
           Enum.flat_map(talent_spell_ids, &SpellPetAuraLoader.pet_aura_ids(&1, Guid.entry(pet_guid))) do
      level = character.unit.level || 1

      aura_ids
      |> Enum.uniq()
      |> Enum.reduce(character, fn aura_id, acc ->
        Event.enqueue(acc, Event.trigger_spell(pet_guid, level, pet_guid, aura_id))
      end)
      |> EventSink.emit_pending()
    else
      _no_links -> character
    end
  end
end
