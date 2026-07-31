defmodule ThistleTea.Game.Player.Reputation do
  @moduledoc """
  Player-session boundary for reputation transitions, client projection, and
  data-driven quest and creature rewards.
  """

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Data.Reputation.Change
  alias ThistleTea.Game.Entity.Data.Reputation.Definition
  alias ThistleTea.Game.Entity.Data.Reputation.KillReward
  alias ThistleTea.Game.Entity.Data.Reputation.State
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.Entity.Logic.Reputation, as: ReputationLogic
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Loader.Reputation, as: ReputationLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Presence

  @alliance_races [1, 3, 4, 7]
  @horde_races [2, 5, 6, 8]
  @faction_slots 64

  def send_initial(%Character{} = character) do
    states = character.player.reputation.states

    factions =
      Enum.map(0..(@faction_slots - 1), fn index ->
        case Enum.find_value(states, &state_at_index(&1, index)) do
          %State{flags: flags, standing: standing} -> {flags, standing}
          nil -> {0, 0}
        end
      end)

    Network.send_packet(%Message.SmsgInitializeFactions{factions: factions})
  end

  def standing(%Character{} = character, faction_id) do
    ReputationLogic.standing(
      character.player.reputation,
      ReputationLoader.catalog(),
      faction_id,
      character.unit.race,
      character.unit.class
    )
  end

  def standings(%Character{} = character) do
    ReputationLoader.catalog().factions
    |> Map.keys()
    |> Map.new(&{&1, standing(character, &1)})
  end

  def projection(%Character{} = character) do
    character
    |> standings()
    |> Map.new(fn {faction_id, standing} ->
      state = ReputationLogic.state(character.player.reputation, faction_id)

      {faction_id,
       %{
         rank: ReputationLogic.rank(standing),
         at_war?: state != nil and ReputationLogic.at_war?(character.player.reputation, faction_id)
       }}
    end)
  end

  def rank(%Character{} = character, faction_id) do
    character
    |> standing(faction_id)
    |> ReputationLogic.rank()
  end

  def modify(%{character: %Character{} = character} = state, faction_id, delta, opts \\ []) do
    catalog = ReputationLoader.catalog()
    previous = character.player.reputation

    {reputation, changes} =
      ReputationLogic.modify(previous, catalog, faction_id, delta, context(character),
        spillover?: Keyword.get(opts, :spillover?, true)
      )

    apply_transition(state, previous, reputation, changes)
  end

  def set(%{character: %Character{} = character} = state, faction_id, value) do
    catalog = ReputationLoader.catalog()
    previous = character.player.reputation
    {reputation, changes} = ReputationLogic.set(previous, catalog, faction_id, value, context(character))
    apply_transition(state, previous, reputation, changes)
  end

  def set_visible(%{character: %Character{} = character} = state, faction_id) do
    case ReputationLogic.set_visible(character.player.reputation, faction_id) do
      {:ok, reputation, change} ->
        Network.send_packet(%Message.SmsgSetFactionVisible{index: change.index})
        store_reputation(state, reputation, false)

      {:error, :not_allowed} ->
        state
    end
  end

  def reveal_target(%{character: %Character{} = character} = state, target_guid) do
    target =
      case Metadata.query(target_guid, [:faction_template, :faction_can_have_reputation?]) do
        metadata when is_map(metadata) -> Map.put(metadata, :guid, target_guid)
        _ -> nil
      end

    with %{faction_can_have_reputation?: true, faction_template: %FactionTemplate{faction: faction_id}} <-
           target,
         false <- Hostility.hostile?(character, target) do
      set_visible(state, faction_id)
    else
      _ -> state
    end
  end

  def set_at_war(%{character: %Character{} = character} = state, index, enabled, opts \\ []) do
    catalog = ReputationLoader.catalog()
    previous = character.player.reputation

    case ReputationLogic.set_at_war(previous, catalog, index, enabled, context(character)) do
      {:ok, reputation, _change} ->
        if Keyword.get(opts, :notify?, false) do
          Network.send_packet(%Message.SmsgSetFactionAtwar{index: index, enabled: enabled})
        end

        store_reputation(state, reputation, false)

      {:error, :not_allowed} ->
        state
    end
  end

  def set_inactive(%{character: %Character{} = character} = state, index, enabled) do
    previous = character.player.reputation

    case ReputationLogic.set_inactive(previous, index, enabled) do
      {:ok, reputation, _change} -> store_reputation(state, reputation, false)
      {:error, :not_allowed} -> state
    end
  end

  def set_watched(%{character: %Character{} = character} = state, index)
      when index == -1 or (index >= 0 and index < @faction_slots) do
    player = %{character.player | watched_faction_index: index}
    character = %{character | player: player}
    CharacterStore.put(character)
    %{state | character: character}
  end

  def set_watched(state, _index), do: state

  def reward_quest(state, %Quest{} = quest) do
    content_level = if quest.level < 0, do: state.character.unit.level, else: quest.level

    Enum.reduce(quest.reward_reputation, state, fn reward, state ->
      delta = reputation_gain(state.character, :quest, reward.value, reward.faction_id, content_level)
      modify(state, reward.faction_id, delta, spillover?: not reward.no_spillover?)
    end)
  end

  def reward_spell(%{character: %Character{} = character} = state, faction_id, value) do
    modify(state, faction_id, reputation_gain(character, :spell, value, faction_id, character.unit.level))
  end

  def reward_kill(%{character: %Character{} = character} = state, creature_entry, creature_level) do
    catalog = ReputationLoader.catalog()
    team = team_for_race(character.unit.race)

    catalog.kill_rewards
    |> Map.get(creature_entry, [])
    |> Enum.filter(&(&1.team in [:both, team]))
    |> Enum.reduce(state, fn %KillReward{} = reward, state ->
      reward_kill_entry(state, reward, creature_level, catalog)
    end)
  end

  defp reward_kill_entry(state, %KillReward{} = reward, creature_level, catalog) do
    if ReputationLogic.rank_value(rank(state.character, reward.faction_id)) <= reward.max_rank do
      delta = reputation_gain(state.character, :kill, reward.value, reward.faction_id, creature_level)
      state = modify(state, reward.faction_id, delta)

      case {reward.team_award?, Map.get(catalog.factions, reward.faction_id)} do
        {true, %Definition{parent_faction_id: parent_id}} when parent_id > 0 ->
          modify(state, parent_id, div(delta, 2), spillover?: false)

        _ ->
          state
      end
    else
      state
    end
  end

  defp reputation_gain(character, source, value, faction_id, content_level) do
    catalog = ReputationLoader.catalog()
    rate = catalog.rates |> Map.get(faction_id, %{}) |> Map.get(source, 1.0)

    if rate <= 0 do
      0
    else
      bonus = if value > 0, do: reputation_bonus(character, source, faction_id), else: 0
      level_rate = ReputationLogic.level_rate(source, value, character.unit.level, content_level)
      ReputationLogic.calculate_gain(value, rate, level_rate, bonus)
    end
  end

  defp reputation_bonus(character, source, faction_id) do
    general = Aura.flat_amount(character, :mod_reputation_gain)

    faction =
      if source == :kill do
        character
        |> Aura.misc_amounts(:mod_faction_reputation_gain)
        |> Enum.reduce(0, fn
          {^faction_id, amount}, total -> total + amount
          _entry, total -> total
        end)
      else
        0
      end

    general + faction
  end

  defp apply_transition(state, previous, reputation, changes) do
    Enum.each(changes, fn %Change{} = change ->
      previous_state = Map.get(previous.states, change.faction_id)

      if not visible?(previous_state) and visible?(change) do
        Network.send_packet(%Message.SmsgSetFactionVisible{index: change.index})
      end
    end)

    put_reputation(state, reputation, changes)
  end

  defp put_reputation(%{character: %Character{}} = state, reputation, changes) do
    if changes != [] do
      Network.send_packet(%Message.SmsgSetFactionStanding{
        standings: Enum.map(changes, &{&1.index, &1.standing})
      })
    end

    store_reputation(state, reputation, true)
  end

  defp store_reputation(%{character: %Character{} = character} = state, reputation, recheck_quests?) do
    player = %{character.player | reputation: reputation}
    character = %{character | player: player}
    CharacterStore.put(character)
    Presence.sync(character, %{reputation: projection(character)})

    if recheck_quests? do
      Quests.on_reputation_changed(%{state | character: character})
    else
      %{state | character: character}
    end
  end

  defp visible?(%{flags: flags}), do: (flags &&& 0x01) != 0
  defp visible?(_state), do: false

  defp state_at_index({_faction_id, %State{index: index} = state}, index), do: state
  defp state_at_index(_entry, _index), do: nil

  defp context(%Character{} = character), do: %{race: character.unit.race, class: character.unit.class}

  defp team_for_race(race) when race in @alliance_races, do: :alliance
  defp team_for_race(race) when race in @horde_races, do: :horde
  defp team_for_race(_race), do: :neutral
end
