defmodule ThistleTea.Game.Battleground.Roster do
  @moduledoc "Shared pure player admission, combat credit, resurrection queues, and honor bookkeeping."

  alias ThistleTea.Game.Battleground.Defeat
  alias ThistleTea.Game.Battleground.Effects
  alias ThistleTea.Game.Battleground.Player
  alias ThistleTea.Game.Battleground.Result

  def new(reservations) do
    Map.new(reservations, fn reservation ->
      player = struct!(Player, reservation)
      {player.guid, player}
    end)
  end

  def disconnect(match, guid) do
    %Result{match: update_player(match, guid, &%{&1 | status: :offline})}
  end

  def leave(match, guid) do
    case Map.pop(match.players, guid) do
      {nil, _players} ->
        %Result{match: match}

      {%Player{} = player, players} ->
        effects = if player.status in [:inside, :offline], do: [%Effects.PlayerLeft{guid: guid}], else: []
        match = %{match | players: players, resurrection_queue: MapSet.delete(match.resurrection_queue, guid)}
        %Result{match: match, effects: effects}
    end
  end

  def scoreboard(match, objective_fields) do
    match.players
    |> Map.values()
    |> Enum.sort_by(& &1.guid)
    |> Enum.map(fn player ->
      %{
        guid: player.guid,
        rank: 4,
        killing_blows: player.killing_blows,
        honorable_kills: player.honorable_kills,
        deaths: player.deaths,
        bonus_honor: player.bonus_honor,
        fields: objective_fields.(player)
      }
    end)
  end

  def enter(%{players: _players} = match, guid, return_to) do
    case Map.get(match.players, guid) do
      %Player{} = player ->
        player = %{player | status: :inside, return_to: return_to}
        match = put_player(match, player)
        %Result{match: match, effects: [%Effects.PlayerJoined{guid: guid}]}

      nil ->
        %Result{match: match}
    end
  end

  def reserve(%{phase: phase, players: _players} = match, reservations) when phase in [:countdown, :active] do
    players =
      Enum.reduce(reservations, match.players, fn reservation, players ->
        player = struct(Player, reservation)
        Map.put_new(players, player.guid, player)
      end)

    %Result{match: %{match | players: players}}
  end

  def reserve(%{players: _players} = match, _reservations), do: %Result{match: match}

  def reconnect(%{players: _players} = match, guid) do
    case Map.get(match.players, guid) do
      %Player{} = player ->
        player = %{player | status: :inside}
        %Result{match: put_player(match, player), effects: [%Effects.PlayerJoined{guid: guid}]}

      nil ->
        %Result{match: match}
    end
  end

  def queue_resurrection(%{players: _players} = match, guid) do
    case Map.get(match.players, guid) do
      %Player{status: :inside} ->
        %Result{match: %{match | resurrection_queue: MapSet.put(match.resurrection_queue, guid)}}

      _ ->
        %Result{match: match}
    end
  end

  def cancel_resurrection(match, guid) do
    %Result{match: %{match | resurrection_queue: MapSet.delete(match.resurrection_queue, guid)}}
  end

  def update_death_scores(match, %Defeat{} = defeat) do
    match =
      if defeat.count_death?,
        do: update_player(match, defeat.victim_guid, &%{&1 | deaths: &1.deaths + 1}),
        else: match

    victim = Map.fetch!(match.players, defeat.victim_guid)

    case Map.get(match.players, defeat.killer_guid) do
      %Player{status: :inside, team: team} when team != victim.team ->
        match = update_player(match, defeat.killer_guid, &%{&1 | killing_blows: &1.killing_blows + 1})

        [defeat.killer_guid | defeat.nearby_guids]
        |> Enum.uniq()
        |> Enum.reduce(match, &credit_team_kill(&2, &1, team))

      _ineligible ->
        match
    end
  end

  defp credit_team_kill(match, guid, team) do
    case Map.get(match.players, guid) do
      %Player{status: :inside, team: ^team} ->
        update_player(match, guid, &%{&1 | honorable_kills: &1.honorable_kills + 1})

      _ineligible ->
        match
    end
  end

  def put_player(match, %Player{} = player), do: %{match | players: Map.put(match.players, player.guid, player)}

  def update_player(match, guid, update) do
    case Map.get(match.players, guid) do
      %Player{} = player -> put_player(match, update.(player))
      nil -> match
    end
  end

  def reward_team_bonus(match, team, amount) do
    guids =
      match.players
      |> Map.values()
      |> Enum.filter(&(&1.team == team and &1.status == :inside))
      |> Enum.map(& &1.guid)
      |> Enum.sort()

    players =
      Enum.reduce(guids, match.players, fn guid, players ->
        Map.update!(players, guid, &%{&1 | bonus_honor: &1.bonus_honor + amount})
      end)

    {%{match | players: players}, %Effects.RewardHonor{guids: guids, amount: amount}}
  end
end
