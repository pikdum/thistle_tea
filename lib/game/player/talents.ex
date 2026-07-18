defmodule ThistleTea.Game.Player.Talents do
  @moduledoc """
  Boundary for spending and resetting talent points: validates the request
  through the pure talent rules, teaches the rank spell, applies any new
  passive auras, and resyncs the unspent-points field on the client.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Talents, as: LogicTalents
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Player.Spells
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Loader.Talent, as: TalentLoader

  def learn(%{character: %Character{} = character} = state, talent_id, requested_rank) do
    with {:ok, talent_spell_ids} <- LogicTalents.validate(character, talent_id, requested_rank),
         {:ok, character, _events} <- Spells.learn(character, with_dependent_spells(talent_spell_ids)) do
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
end
