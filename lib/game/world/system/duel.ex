defmodule ThistleTea.Game.World.System.Duel do
  @moduledoc """
  Serializes duel pairs, owns countdown and boundary timers, and projects each
  transition to the participating player processes and clients.
  """
  use GenServer

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Duel
  alias ThistleTea.Game.Duel.Admission
  alias ThistleTea.Game.Duel.Match
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.Exploration, as: ExplorationLoader
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: GameObjectTemplateLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  @countdown_ms 3_000
  @bounds_tick_ms 1_000
  @winner_range 250
  @grovel_spell_id 7_267
  @area_flag_duel 0x40
  @table_options [:named_table, :public, read_concurrency: true]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def challenge(attrs, server \\ __MODULE__) when is_map(attrs) do
    GenServer.call(server, {:challenge, attrs})
  end

  def challenge_admission(initiator_guid, opponent_guid, world, server \\ __MODULE__) do
    GenServer.call(server, {:challenge_admission, initiator_guid, opponent_guid, world})
  catch
    :exit, _ -> nil
  end

  def accept(guid, server \\ __MODULE__) when is_integer(guid) do
    GenServer.call(server, {:accept, guid})
  end

  def cancel(guid, server \\ __MODULE__) when is_integer(guid) do
    GenServer.call(server, {:cancel, guid})
  end

  def defeat(loser_guid, winner_guid, server \\ __MODULE__) when is_integer(loser_guid) and is_integer(winner_guid) do
    GenServer.cast(server, {:defeat, loser_guid, winner_guid})
  end

  def disconnect(guid, server \\ __MODULE__) when is_integer(guid) do
    GenServer.call(server, {:disconnect, guid})
  catch
    :exit, _ -> :ok
  end

  def interrupt(guid, server \\ __MODULE__) when is_integer(guid) do
    GenServer.cast(server, {:interrupt, guid})
  end

  def busy?(guid, server \\ __MODULE__) when is_integer(guid) do
    GenServer.call(server, {:busy?, guid})
  catch
    :exit, _ -> false
  end

  def match(guid, server \\ __MODULE__) when is_integer(guid) do
    GenServer.call(server, {:match, guid})
  catch
    :exit, _ -> nil
  end

  def active_opponents?(first_guid, second_guid, table \\ __MODULE__)

  def active_opponents?(first_guid, second_guid, table) when is_integer(first_guid) and is_integer(second_guid) do
    first_owner = controlling_player(first_guid)
    second_owner = controlling_player(second_guid)

    case lookup(table, first_owner) do
      %{opponent_guid: ^second_owner, state: :started} -> true
      _ -> false
    end
  end

  def active_opponents?(_first_guid, _second_guid, _table), do: false

  @impl GenServer
  def init(opts) do
    table = Keyword.get(opts, :table, __MODULE__)
    init_table(table)

    {:ok,
     %{
       duels: %Duel{},
       table: table,
       start_refs: %{},
       bounds_refs: %{},
       spawn_flag: Keyword.get(opts, :spawn_flag, &spawn_flag/1),
       despawn_flag: Keyword.get(opts, :despawn_flag, &World.stop_entity/1),
       send_packet: Keyword.get(opts, :send_packet, &Network.send_packet/2),
       broadcast_winner: Keyword.get(opts, :broadcast_winner, &broadcast_winner/2),
       sync_player: Keyword.get(opts, :sync_player, &Entity.duel_update/2),
       stop_pet: Keyword.get(opts, :stop_pet, &stop_pet/2),
       trigger_spell: Keyword.get(opts, :trigger_spell, &trigger_spell/2),
       position: Keyword.get(opts, :position, &World.position/1),
       online?: Keyword.get(opts, :online?, &Entity.online?/1),
       dueling_allowed?: Keyword.get(opts, :dueling_allowed?, &dueling_allowed?/1),
       player_name: Keyword.get(opts, :player_name, &player_name/1),
       now: Keyword.get(opts, :now, &Time.now/0),
       countdown_ms: Keyword.get(opts, :countdown_ms, @countdown_ms),
       bounds_tick_ms: Keyword.get(opts, :bounds_tick_ms, @bounds_tick_ms)
     }}
  end

  @impl GenServer
  def handle_call({:challenge, attrs}, _from, state) do
    initiator_guid = Map.get(attrs, :initiator_guid)
    opponent_guid = Map.get(attrs, :opponent_guid)

    admission = build_admission(state, initiator_guid, opponent_guid, Map.get(attrs, :world))

    with :ok <- validate_challenge_attrs(attrs),
         :ok <- Duel.validate_admission(admission),
         {:ok, arbiter_guid} <- state.spawn_flag.(attrs),
         {:ok, match, duels} <-
           Duel.challenge(state.duels, admission, %{
             arbiter_guid: arbiter_guid,
             world: Map.get(attrs, :world),
             flag_position: Map.get(attrs, :flag_position)
           }) do
      state = %{state | duels: duels}
      index_match(state, match)
      sync_requested(state, match)
      send_requested(state, match)
      {:reply, {:ok, match}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:challenge_admission, initiator_guid, opponent_guid, world}, _from, state) do
    {:reply, build_admission(state, initiator_guid, opponent_guid, world), state}
  end

  def handle_call({:accept, guid}, _from, state) do
    case Duel.accept(state.duels, guid, state.now.()) do
      {:ok, match, duels} ->
        timer_ref = Process.send_after(self(), {:start_duel, match.id}, state.countdown_ms)
        state = %{state | duels: duels, start_refs: Map.put(state.start_refs, match.id, timer_ref)}
        index_match(state, match)
        send_to_participants(state, match, %Message.SmsgDuelCountdown{time_ms: state.countdown_ms})
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:cancel, guid}, _from, state) do
    case Duel.match_for(state.duels, guid) do
      %Match{state: :started} = match ->
        {:reply, :ok, complete_match(state, match, guid, :defeated)}

      %Match{} = match ->
        {:reply, :ok, complete_match(state, match, guid, :interrupted)}

      nil ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:busy?, guid}, _from, state) do
    {:reply, Duel.busy?(state.duels, guid), state}
  end

  def handle_call({:match, guid}, _from, state) do
    {:reply, Duel.match_for(state.duels, guid), state}
  end

  def handle_call({:disconnect, guid}, _from, state) do
    case Duel.match_for(state.duels, guid) do
      %Match{state: :started} = match ->
        {:reply, :ok, complete_match(state, match, guid, :fled)}

      %Match{} = match ->
        {:reply, :ok, complete_match(state, match, guid, :interrupted)}

      nil ->
        {:reply, :ok, state}
    end
  end

  @impl GenServer
  def handle_cast({:defeat, loser_guid, winner_guid}, state) do
    case Duel.match_for(state.duels, loser_guid) do
      %Match{state: :started} = match ->
        if Duel.opponent(match, loser_guid) == winner_guid do
          {:noreply, complete_match(state, match, loser_guid, :defeated)}
        else
          {:noreply, complete_match(state, match, loser_guid, :interrupted)}
        end

      _match ->
        {:noreply, state}
    end
  end

  def handle_cast({:interrupt, guid}, state) do
    case Duel.match_for(state.duels, guid) do
      %Match{} = match -> {:noreply, complete_match(state, match, guid, :interrupted)}
      nil -> {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:start_duel, match_id}, state) do
    state = %{state | start_refs: Map.delete(state.start_refs, match_id)}

    case Duel.start(state.duels, match_id, state.now.()) do
      {:ok, match, duels} ->
        state = %{state | duels: duels}
        index_match(state, match)
        sync_started(state, match)
        {:noreply, schedule_bounds(state, match.id)}

      {:error, _reason} ->
        {:noreply, state}
    end
  end

  def handle_info({:check_duel_bounds, match_id}, state) do
    state = %{state | bounds_refs: Map.delete(state.bounds_refs, match_id)}

    case Map.get(state.duels.matches, match_id) do
      %Match{} = match ->
        distances = distances_to_flag(state, match)
        {events, duels} = Duel.check_bounds(state.duels, match.id, distances, state.now.())
        state = %{state | duels: duels}

        case Enum.find(events, &match?({:fled, _loser, _winner}, &1)) do
          {:fled, loser_guid, _winner_guid} ->
            {:noreply, complete_match(state, match, loser_guid, :fled)}

          nil ->
            send_bound_events(state, events)
            {:noreply, schedule_bounds(state, match.id)}
        end

      nil ->
        {:noreply, state}
    end
  end

  defp validate_challenge_attrs(attrs) do
    validations = [
      {match?(%WorldRef{}, Map.get(attrs, :world)), :invalid_world},
      {valid_position?(Map.get(attrs, :flag_position)), :invalid_position}
    ]

    case Enum.find(validations, fn {valid?, _reason} -> not valid? end) do
      {_invalid, reason} -> {:error, reason}
      nil -> :ok
    end
  end

  defp build_admission(state, initiator_guid, opponent_guid, world) do
    %Admission{
      initiator_guid: initiator_guid,
      opponent_guid: opponent_guid,
      initiator_player?: player_guid?(initiator_guid),
      opponent_player?: player_guid?(opponent_guid),
      initiator_online?: state.online?.(initiator_guid),
      opponent_online?: state.online?.(opponent_guid),
      initiator_allowed?: state.dueling_allowed?.(initiator_guid),
      opponent_allowed?: state.dueling_allowed?.(opponent_guid),
      same_world?: participants_in_world?(state, [initiator_guid, opponent_guid], world),
      initiator_busy?: Duel.busy?(state.duels, initiator_guid),
      opponent_busy?: Duel.busy?(state.duels, opponent_guid)
    }
  end

  defp complete_match(state, match, loser_guid, reason) do
    winner_guid = Duel.opponent(match, loser_guid)
    started? = reason != :interrupted

    send_to_participants(state, match, %Message.SmsgDuelComplete{started?: started?})

    if started? do
      winner_packet = %Message.SmsgDuelWinner{
        fled?: reason == :fled,
        winner_name: state.player_name.(winner_guid),
        loser_name: state.player_name.(loser_guid)
      }

      state.broadcast_winner.(winner_packet, loser_guid)
    end

    if reason == :defeated, do: state.trigger_spell.(loser_guid, @grovel_spell_id)

    opponent_pets = participant_pets(match)

    Enum.each(Duel.participants(match), fn guid ->
      state.sync_player.(guid, {:finished, finish_payload(match, guid, opponent_pets)})
    end)

    stop_participant_pets(state, match, opponent_pets)
    state.despawn_flag.(match.arbiter_guid)
    {:ok, _match, duels} = Duel.complete(state.duels, loser_guid)

    state
    |> Map.put(:duels, duels)
    |> cancel_timers(match.id)
    |> delete_index(match)
  end

  defp finish_payload(match, guid, participant_pets) do
    opponent_guid = Duel.opponent(match, guid)

    %{
      opponent_guid: opponent_guid,
      opponent_pet_guid: Map.get(participant_pets, opponent_guid),
      started_at: match.started_at,
      now: Time.now()
    }
  end

  defp participant_pets(match) do
    Map.new(Duel.participants(match), fn guid ->
      controlled_guid =
        case Metadata.query(guid, [:controlled_guid]) do
          %{controlled_guid: controlled_guid} when is_integer(controlled_guid) -> controlled_guid
          _ -> nil
        end

      {guid, controlled_guid}
    end)
  end

  defp stop_participant_pets(state, match, participant_pets) do
    Enum.each(Duel.participants(match), fn guid ->
      pet_guid = Map.get(participant_pets, guid)
      opponent_guid = Duel.opponent(match, guid)
      opponent_pet_guid = Map.get(participant_pets, opponent_guid)
      stop_pet_targets(state, pet_guid, [opponent_guid, opponent_pet_guid])
    end)
  end

  defp stop_pet_targets(state, pet_guid, targets) when is_integer(pet_guid) do
    targets
    |> Enum.filter(&is_integer/1)
    |> Enum.each(&state.stop_pet.(pet_guid, &1))
  end

  defp stop_pet_targets(_state, _pet_guid, _targets), do: :ok

  defp sync_requested(state, match) do
    Enum.each(Duel.participants(match), fn guid ->
      state.sync_player.(guid, {
        :requested,
        %{
          initiator_guid: match.initiator_guid,
          opponent_guid: Duel.opponent(match, guid),
          arbiter_guid: match.arbiter_guid
        }
      })
    end)
  end

  defp sync_started(state, match) do
    state.sync_player.(match.initiator_guid, {
      :started,
      %{opponent_guid: match.opponent_guid, team: 1, started_at: match.started_at}
    })

    state.sync_player.(match.opponent_guid, {
      :started,
      %{opponent_guid: match.initiator_guid, team: 2, started_at: match.started_at}
    })
  end

  defp send_requested(state, match) do
    packet = %Message.SmsgDuelRequested{
      arbiter_guid: match.arbiter_guid,
      initiator_guid: match.initiator_guid
    }

    send_to_participants(state, match, packet)
  end

  defp send_to_participants(state, match, packet) do
    Enum.each(Duel.participants(match), &state.send_packet.(packet, &1))
  end

  defp send_bound_events(state, events) do
    Enum.each(events, fn
      {:out_of_bounds, guid} -> state.send_packet.(%Message.SmsgDuelOutofbounds{}, guid)
      {:in_bounds, guid} -> state.send_packet.(%Message.SmsgDuelInbounds{}, guid)
    end)
  end

  defp schedule_bounds(state, match_id) do
    timer_ref = Process.send_after(self(), {:check_duel_bounds, match_id}, state.bounds_tick_ms)
    %{state | bounds_refs: Map.put(state.bounds_refs, match_id, timer_ref)}
  end

  defp cancel_timers(state, match_id) do
    cancel_timer(Map.get(state.start_refs, match_id))
    cancel_timer(Map.get(state.bounds_refs, match_id))

    %{
      state
      | start_refs: Map.delete(state.start_refs, match_id),
        bounds_refs: Map.delete(state.bounds_refs, match_id)
    }
  end

  defp cancel_timer(ref) when is_reference(ref), do: Process.cancel_timer(ref)
  defp cancel_timer(_ref), do: false

  defp distances_to_flag(state, %Match{} = match) do
    Map.new(Duel.participants(match), fn guid ->
      distance =
        case state.position.(guid) do
          {world, x, y, z} when world == match.world ->
            Math.distance(match.flag_position, {x, y, z})

          _position ->
            nil
        end

      {guid, distance}
    end)
  end

  defp index_match(state, match) do
    Enum.each(Duel.participants(match), fn guid ->
      :ets.insert(
        state.table,
        {guid,
         %{
           opponent_guid: Duel.opponent(match, guid),
           arbiter_guid: match.arbiter_guid,
           state: match.state,
           started_at: match.started_at
         }}
      )
    end)
  end

  defp delete_index(state, match) do
    Enum.each(Duel.participants(match), &:ets.delete(state.table, &1))
    state
  end

  defp init_table(table) when is_atom(table) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  defp init_table(table), do: table

  defp lookup(table, guid) when is_integer(guid) do
    case :ets.lookup(table, guid) do
      [{^guid, duel}] -> duel
      _ -> nil
    end
  rescue
    ArgumentError -> nil
  end

  defp lookup(_table, _guid), do: nil

  defp controlling_player(guid) do
    if player_guid?(guid) do
      guid
    else
      case Metadata.query(guid, [:owner_guid]) do
        %{owner_guid: owner_guid} when is_integer(owner_guid) -> owner_guid
        _ -> guid
      end
    end
  end

  defp player_guid?(guid) when is_integer(guid), do: Guid.entity_type(guid) == :player
  defp player_guid?(_guid), do: false

  defp valid_position?({x, y, z}), do: is_number(x) and is_number(y) and is_number(z)
  defp valid_position?(_position), do: false

  defp participants_in_world?(state, guids, world) do
    Enum.all?(guids, fn guid ->
      match?({^world, _x, _y, _z}, state.position.(guid))
    end)
  end

  defp dueling_allowed?(guid) do
    with %{area: area_id} when is_integer(area_id) <- Metadata.query(guid, [:area]),
         %{flags: flags} when is_integer(flags) <- ExplorationLoader.area(area_id) do
      (flags &&& @area_flag_duel) != 0
    else
      _missing -> false
    end
  end

  defp spawn_flag(%{
         initiator_guid: initiator_guid,
         initiator_level: level,
         entry: entry,
         world: %WorldRef{} = world,
         flag_position: {x, y, z},
         orientation: orientation
       })
       when is_integer(entry) and entry > 0 do
    case GameObjectTemplateLoader.get(entry) do
      %GameObjectTemplate{} = template ->
        game_object =
          GameObject.build_summoned(template, world, {x, y, z, orientation || 0.0},
            summoned_by: initiator_guid,
            level: (level || 1) + 1
          )

        case World.start_entity(game_object) do
          {:ok, _pid} -> {:ok, game_object.object.guid}
          :ok -> {:ok, game_object.object.guid}
          {:error, reason} -> {:error, reason}
        end

      _template ->
        {:error, :missing_flag_template}
    end
  end

  defp spawn_flag(_attrs), do: {:error, :invalid_flag}

  defp trigger_spell(guid, spell_id) do
    Entity.trigger_spell(guid, spell_id, guid)
  end

  defp stop_pet(pet_guid, opponent_guid) do
    Entity.drop_threat(pet_guid, opponent_guid)
  end

  defp player_name(guid) do
    case Metadata.query(guid, [:name]) do
      %{name: name} when is_binary(name) -> name
      _ -> Integer.to_string(guid)
    end
  end

  defp broadcast_winner(packet, anchor_guid) do
    case World.position(anchor_guid) do
      {world, x, y, z} ->
        :players
        |> SpatialHash.query(world, x, y, z, @winner_range)
        |> Enum.each(fn {guid, _distance} -> Network.send_packet(packet, guid) end)

      _position ->
        Network.send_packet(packet, anchor_guid)
    end
  end
end
