defmodule ThistleTea.Game.Player.Talents do
  @moduledoc """
  Boundary for spending and resetting talent points: validates the request
  through the pure talent rules, teaches the rank spell, applies any new
  passive auras, and resyncs the unspent-points field on the client.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
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
      character = sync_pet_aura_links(state.character, character, Time.now())
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
        now = Time.now()

        character
        |> Spells.unlearn(with_dependent_spells(talent_spell_ids), now)
        |> then(&sync_pet_aura_links(character, &1, now))
        |> then(&commit(state, &1))
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

  defp sync_pet_aura_links(%Character{} = previous, %Character{} = character, now) do
    case Character.controlled_guid(character) do
      pet_guid when is_integer(pet_guid) ->
        pet_entry = Guid.entry(pet_guid)
        previous_ids = pet_aura_ids(previous, pet_entry)
        current_ids = pet_aura_ids(character, pet_entry)
        removed_ids = previous_ids -- current_ids
        added_ids = current_ids -- previous_ids
        level = character.unit.level || 1

        {character, local_events} =
          Enum.reduce(removed_ids, {character, []}, fn aura_id, {current, events} ->
            {current, aura_events} = AuraLogic.remove_source_spell(current, aura_id, pet_guid, now)
            {current, events ++ aura_events}
          end)

        external_events =
          Enum.map(removed_ids, &Effects.remove_aura(pet_guid, pet_guid, &1)) ++
            Enum.map(added_ids, &Effects.trigger_spell(pet_guid, level, pet_guid, &1))

        character
        |> Effects.enqueue(local_events)
        |> EventSink.emit(external_events)

      _no_pet ->
        character
    end
  end

  defp pet_aura_ids(%Character{internal: internal}, pet_entry) do
    internal.spells
    |> List.wrap()
    |> Enum.flat_map(&SpellPetAuraLoader.pet_aura_ids(&1, pet_entry))
    |> Enum.uniq()
  end
end
