defmodule ThistleTea.Game.Player.Battlegrounds do
  @moduledoc """
  Player boundary for battleground admission, status, travel, and queries.
  """

  alias ThistleTea.Game.Battleground
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Party.Group
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Battleground.Match
  alias ThistleTea.Game.World.Loader.Battleground, as: BattlegroundLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.System.Battleground, as: BattlegroundSystem
  alias ThistleTea.Game.World.System.Party, as: PartySystem

  @interaction_range 10.0

  def battlemaster_hello(%{ready: true, character: %Character{} = character} = state, guid) do
    entry = Guid.entry(guid)

    if BattlegroundLoader.battlemaster?(entry) and nearby?(character, guid) do
      template = BattlegroundLoader.template_for_battlemaster(entry)
      send_list(state, template.map_id, guid)
    end

    state
  end

  def list(%{ready: true} = state, map_id), do: send_list(state, map_id, 0)
  def list(state, _map_id), do: state

  def join(state, map_id, join_as_group?, instance_id \\ 0)

  def join(%{ready: true, character: %Character{}} = state, map_id, join_as_group?, instance_id) do
    result =
      if join_as_group?,
        do: join_group(state, map_id, instance_id),
        else: queue_players([snapshot(state)], map_id, instance_id)

    case result do
      {:ok, guids} -> Enum.each(guids, &notify_queued(&1, map_id))
      _error -> :ok
    end

    state
  end

  def join(state, _map_id, _join_as_group?, _instance_id), do: state

  def send_status(%{ready: true, guid: guid} = state) do
    guid
    |> BattlegroundSystem.status()
    |> status_packet()
    |> Network.send_packet()

    state
  end

  def send_status(state), do: state

  def port(%{ready: true, character: %Character{} = character} = state, action) when action in [0, 1] do
    return_to = return_destination(character)

    case BattlegroundSystem.port(state.guid, action, return_to) do
      {:ok, world, {x, y, z, orientation}} ->
        GenServer.cast(self(), {:start_teleport, x, y, z, orientation, world})

      _ ->
        :ok
    end

    send_status(state)
  end

  def port(state, _action), do: state

  def leave(%{ready: true, character: %Character{} = character} = state) do
    case BattlegroundSystem.leave(state.guid, character.movement_block.position) do
      {:ok, {world, {x, y, z, orientation}}} ->
        GenServer.cast(self(), {:start_teleport, x, y, z, orientation, world})

      _ ->
        :ok
    end

    state
  end

  def leave(state), do: state

  def spirit_healer_time(%{ready: true, character: %Character{} = character} = state, healer_guid) do
    if not Death.alive?(character) and spirit_guide?(character, healer_guid) do
      case BattlegroundSystem.spirit_healer_time(character.internal.world) do
        time_ms when is_integer(time_ms) ->
          Network.send_packet(%Message.SmsgAreaSpiritHealerTime{guid: healer_guid, time_ms: time_ms})

        _ ->
          :ok
      end
    end

    state
  end

  def spirit_healer_time(state, _healer_guid), do: state

  def queue_resurrection(%{ready: true, character: %Character{} = character} = state, healer_guid) do
    if not Death.alive?(character) and spirit_guide?(character, healer_guid) do
      BattlegroundSystem.queue_resurrection(character.internal.world, state.guid)
    end

    state
  end

  def queue_resurrection(state, _healer_guid), do: state

  def scoreboard(%{ready: true, character: %Character{} = character} = state) do
    players = BattlegroundSystem.scoreboard(character.internal.world)
    Network.send_packet(%Message.MsgPvpLogData{players: players})
    state
  end

  def scoreboard(state), do: state

  def positions(%{ready: true, character: %Character{} = character} = state) do
    world = character.internal.world

    with pid when is_pid(pid) <- BattlegroundSystem.match_for_world(world) do
      send_positions(Match.snapshot(pid), world, state.guid)
    end

    state
  end

  def positions(state), do: state

  defp send_list(state, map_id, battlemaster_guid) do
    result = BattlegroundSystem.list(map_id, state.character.unit.level)

    if result.template do
      Network.send_packet(%Message.SmsgBattlefieldList{
        guid: battlemaster_guid,
        map: map_id,
        bracket: result.bracket || 0,
        instances: result.instances
      })
    end

    state
  end

  defp join_group(state, map_id, instance_id) do
    case PartySystem.group_of(state.guid) do
      %Group{leader: leader, members: members} when leader == state.guid ->
        queue_group_members(members, map_id, instance_id)

      %Group{} ->
        {:error, :not_leader}

      nil ->
        queue_players([snapshot(state)], map_id, instance_id)
    end
  end

  defp snapshot(%{guid: guid, character: %Character{} = character}) do
    %{
      guid: guid,
      name: character.internal.name,
      team: Battleground.team_for_race(character.unit.race),
      level: character.unit.level
    }
  end

  defp snapshot(%{guid: guid}) do
    case Metadata.query(guid, [:name, :race, :level]) do
      %{name: name, race: race, level: level} ->
        %{guid: guid, name: name, team: Battleground.team_for_race(race), level: level}

      _missing ->
        nil
    end
  end

  defp collect_snapshots(players) do
    if Enum.any?(players, &is_nil/1), do: :error, else: {:ok, players}
  end

  defp queue_group_members(members, map_id, instance_id) do
    members
    |> Enum.map(&snapshot/1)
    |> collect_snapshots()
    |> case do
      {:ok, players} -> queue_players(players, map_id, instance_id)
      :error -> {:error, :member_offline}
    end
  end

  defp queue_players(players, map_id, instance_id) do
    case BattlegroundSystem.join_group_for_instance(players, map_id, instance_id) do
      :ok -> {:ok, Enum.map(players, & &1.guid)}
      error -> error
    end
  end

  defp status_packet(%{status: :none}), do: %Message.SmsgBattlefieldStatus{}

  defp status_packet(%{status: :wait_queue} = status) do
    %Message.SmsgBattlefieldStatus{
      map: status.map_id,
      bracket: status.bracket,
      status: :wait_queue,
      time_two_ms: status.elapsed_ms
    }
  end

  defp status_packet(%{status: :wait_join} = status) do
    %Message.SmsgBattlefieldStatus{
      map: status.map_id,
      bracket: status.bracket,
      client_instance_id: status.client_instance_id,
      status: :wait_join,
      time_one_ms: 80_000
    }
  end

  defp status_packet(%{status: :in_progress} = status) do
    %Message.SmsgBattlefieldStatus{
      map: status.map_id,
      bracket: status.bracket,
      client_instance_id: status.client_instance_id,
      status: :in_progress,
      time_one_ms: status.auto_leave_ms,
      time_two_ms: max(Time.now() - status.started_at, 0)
    }
  end

  defp return_destination(character) do
    {x, y, z, orientation} = character.movement_block.position
    {character.internal.world, {x, y, z, orientation}}
  end

  defp nearby?(character, guid) do
    with {world, x, y, z} <- World.position(character),
         {^world, target_x, target_y, target_z} <- World.position(guid) do
      Math.distance({x, y, z}, {target_x, target_y, target_z}) <= @interaction_range
    else
      _missing -> false
    end
  end

  defp positions_for(match, world, predicate) do
    match.players
    |> Map.values()
    |> Enum.filter(&(&1.status == :inside and predicate.(&1)))
    |> Enum.flat_map(&position_entry(world, &1.guid))
  end

  defp send_positions(match, world, guid) do
    case Map.get(match.players, guid) do
      nil ->
        :ok

      player ->
        teammates = positions_for(match, world, &(&1.team == player.team))
        carriers = carrier_positions(match, world, player.team)
        Network.send_packet(%Message.MsgBattlegroundPlayerPositions{teammates: teammates, carriers: carriers})
    end
  end

  defp carrier_positions(match, world, team) do
    flag_team = if team == :alliance, do: :horde, else: :alliance

    case Map.fetch!(match.flags, flag_team) do
      %{state: :carried, carrier: guid} -> position_entry(world, guid)
      _flag -> []
    end
  end

  defp position_entry(world, guid) do
    case World.position(guid) do
      {^world, x, y, _z} -> [%{guid: guid, x: x, y: y}]
      _missing -> []
    end
  end

  defp notify_queued(guid, map_id) do
    Network.send_packet(%Message.SmsgGroupJoinedBattleground{result: map_id}, guid)
    Network.send_packet(status_packet(BattlegroundSystem.status(guid)), guid)
  end

  defp spirit_guide?(character, guid) do
    Guid.entry(guid) in BattlegroundLoader.spirit_guide_entries() and nearby?(character, guid)
  end
end
