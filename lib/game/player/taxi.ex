defmodule ThistleTea.Game.Player.Taxi do
  @moduledoc """
  Player taxi boundary for flight-master interaction, node discovery, and
  route activation.
  """
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Taxi.Network, as: TaxiNetwork
  alias ThistleTea.Game.Entity.Data.Taxi.Node
  alias ThistleTea.Game.Entity.Data.Taxi.Path
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Entity.Logic.Taxi, as: TaxiLogic
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Entity.Server.Player.CompanionOwner
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Reputation
  alias ThistleTea.Game.Player.Spellcasting
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Loader.Taxi, as: TaxiLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Presence
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.Visibility

  @flightmaster_flag 0x00000008
  @interaction_distance 5.0
  @taxi_start_distance :math.sqrt(1_000.0)
  @reply_ok 0
  @reply_unspecified 1
  @reply_no_such_path 2
  @reply_not_enough_money 3
  @reply_no_vendor_nearby 5
  @reply_not_visited 6
  @reply_player_busy 7
  @reply_player_already_mounted 8
  @reply_player_shapeshifted 9
  @reply_same_node 11
  @reply_not_standing 12
  @alliance_races [1, 3, 4, 7]
  @horde_races [2, 5, 6, 8]

  def status(state, flightmaster_guid), do: status(state, flightmaster_guid, TaxiLoader.get())

  def status(%{character: %Character{} = character} = state, flightmaster_guid, %TaxiNetwork{} = network) do
    with {:ok, %Node{id: node_id}} <- flightmaster_node(character, flightmaster_guid, network) do
      Network.send_packet(%Message.SmsgTaxinodeStatus{
        guid: flightmaster_guid,
        known?: known?(character, node_id)
      })
    end

    state
  end

  def status(state, _flightmaster_guid, _network), do: state

  def query(state, flightmaster_guid), do: query(state, flightmaster_guid, TaxiLoader.get())

  def query(%{character: %Character{} = character} = state, flightmaster_guid, %TaxiNetwork{} = network) do
    case flightmaster_node(character, flightmaster_guid, network) do
      {:ok, %Node{id: node_id}} ->
        if known?(character, node_id) do
          send_menu(character, flightmaster_guid, node_id, network)
          state
        else
          discover(state, flightmaster_guid, node_id)
        end

      _invalid ->
        state
    end
  end

  def query(state, _flightmaster_guid, _network), do: state

  def activate(state, flightmaster_guid, node_ids), do: activate(state, flightmaster_guid, node_ids, TaxiLoader.get())

  def activate(
        %{ready: true, character: %Character{} = character} = state,
        flightmaster_guid,
        node_ids,
        %TaxiNetwork{} = network
      )
      when is_list(node_ids) do
    with {:ok, %Node{id: source_node_id}} <- flightmaster_node(character, flightmaster_guid, network),
         :ok <- validate_activation(character, node_ids, source_node_id),
         {:ok, itinerary} <- TaxiNetwork.itinerary(network, node_ids),
         itinerary = discounted_itinerary(character, flightmaster_guid, itinerary),
         :ok <- validate_itinerary(character, itinerary, network),
         {:ok, mount_display_id} <- mount_display_id(character, source_node_id, network),
         :ok <- validate_fare(character, itinerary.total_cost) do
      send_reply(@reply_ok)
      start_flight(state, itinerary, mount_display_id, network, true)
    else
      {:error, reason} ->
        send_reply(reply_for(reason))
        state
    end
  end

  def activate(state, _flightmaster_guid, _node_ids, _network), do: state

  def start_path(state, path_id), do: start_path(state, path_id, TaxiLoader.get())

  def start_path(%{ready: true, character: %Character{} = character} = state, path_id, %TaxiNetwork{} = network)
      when is_integer(path_id) do
    with true <- Death.alive?(character),
         false <- TaxiLogic.active?(character),
         true <- character.internal.in_combat != true,
         %Path{} = path <- TaxiNetwork.path(network, path_id),
         %Node{} = source <- TaxiNetwork.node(network, path.source_node_id),
         :ok <- validate_source_position(character, source),
         itinerary = %{paths: [path], nodes: path.nodes, total_cost: 0},
         :ok <- validate_itinerary(character, itinerary, network),
         {:ok, mount_display_id} <- mount_display_id(character, path.source_node_id, network) do
      send_reply(@reply_ok)
      start_flight(state, itinerary, mount_display_id, network, false)
    else
      _invalid -> state
    end
  end

  def start_path(state, _path_id, _network), do: state

  def arrive(%{character: %Character{internal: %{taxi_flight: %{token: token}}}} = state, token)
      when is_reference(token) do
    cancel_arrival(state)
    character = TaxiLogic.finish(state.character, Time.now())
    World.update_position(character)

    state =
      %{state | character: character, taxi_arrival_ref: nil}
      |> PlayerServer.maybe_broadcast_update()

    CharacterStore.put(state.character)
    send(self(), :restore_companion)
    state
  end

  def arrive(state, _token), do: state

  def progress(%{character: %Character{internal: %{taxi_flight: %{token: token}}}} = state, token)
      when is_reference(token) do
    now = Time.now()

    if Movement.remaining_move_duration(state.character, now) == 0 do
      arrive(state, token)
    else
      character = Movement.sync_position(state.character, now)
      Presence.relocate(character)

      state
      |> Map.put(:character, character)
      |> Visibility.refresh_player()
      |> schedule_progress(token, now)
    end
  end

  def progress(state, _token), do: state

  def disconnect(%{character: %Character{} = character} = state) do
    cancel_arrival(state)

    if TaxiLogic.active?(character) do
      character = TaxiLogic.finish(character, Time.now())
      World.update_position(character)
      %{state | character: character, taxi_arrival_ref: nil}
    else
      %{state | taxi_arrival_ref: nil}
    end
  end

  def disconnect(state), do: state

  def unlock_all(%{character: %Character{player: player} = character} = state, %TaxiNetwork{} = network) do
    player = %{player | taxi_nodes: network.network_node_ids}
    character = %{character | player: player}
    CharacterStore.put(character)
    %{state | character: character}
  end

  def unlock_all(state, _network), do: state

  def known?(%Character{player: %{taxi_nodes: %MapSet{} = known}}, node_id) do
    MapSet.member?(known, node_id)
  end

  def known?(%Character{}, _node_id), do: false

  def team_for_race(race) when race in @alliance_races, do: :alliance
  def team_for_race(race) when race in @horde_races, do: :horde
  def team_for_race(_race), do: :neutral

  defp validate_activation(character, [source_node_id | _] = node_ids, source_node_id) do
    with :ok <- validate_player_available(character),
         :ok <- validate_mount_state(character) do
      validate_route_access(character, node_ids, source_node_id)
    end
  end

  defp validate_activation(_character, _node_ids, _source_node_id), do: {:error, :no_such_path}

  defp validate_player_available(character) do
    if Death.alive?(character) and not TaxiLogic.active?(character) and character.internal.in_combat != true and
         is_nil(character.internal.casting) do
      :ok
    else
      {:error, :player_busy}
    end
  end

  defp validate_mount_state(character) do
    cond do
      (character.unit.mount_display_id || 0) != 0 -> {:error, :already_mounted}
      (character.unit.shapeshift_form || 0) != 0 -> {:error, :shapeshifted}
      (character.unit.stand_state || 0) != 0 -> {:error, :not_standing}
      true -> :ok
    end
  end

  defp validate_route_access(character, node_ids, source_node_id) do
    cond do
      List.last(node_ids) == source_node_id -> {:error, :same_node}
      Enum.any?(node_ids, &(not known?(character, &1))) -> {:error, :not_visited}
      true -> :ok
    end
  end

  defp validate_itinerary(%Character{internal: %{world: world}}, itinerary, network) do
    destination = TaxiNetwork.node(network, List.last(itinerary.paths).destination_node_id)

    if itinerary.nodes != [] and match?(%Node{map_id: map_id} when map_id == world.map_id, destination) and
         Enum.all?(itinerary.nodes, &(&1.map_id == world.map_id)) do
      :ok
    else
      {:error, :no_such_path}
    end
  end

  defp validate_fare(%Character{player: player}, fare) when is_integer(fare) and fare >= 0 do
    if (player.coinage || 0) >= fare, do: :ok, else: {:error, :not_enough_money}
  end

  defp validate_fare(%Character{}, _fare), do: {:error, :unspecified}

  defp discounted_itinerary(character, flightmaster_guid, itinerary) do
    total_cost =
      Enum.reduce(itinerary.paths, 0, fn path, total ->
        total + Reputation.price(character, flightmaster_guid, path.cost)
      end)

    %{itinerary | total_cost: total_cost}
  end

  defp validate_source_position(%Character{internal: %{world: world}, movement_block: %{position: position}}, %Node{
         map_id: map_id,
         position: source_position
       }) do
    if map_id == world.map_id and SpatialHash.distance(xyz(position), source_position) <= @taxi_start_distance do
      :ok
    else
      {:error, :too_far_away}
    end
  end

  defp mount_display_id(%Character{unit: unit}, source_node_id, network) do
    with %Node{mount_display_ids: mount_display_ids} <- TaxiNetwork.node(network, source_node_id),
         mount_display_id when is_integer(mount_display_id) and mount_display_id > 0 <-
           Map.get(mount_display_ids, team_for_race(unit.race)) do
      {:ok, mount_display_id}
    else
      _missing -> {:error, :no_such_path}
    end
  end

  defp start_flight(state, itinerary, mount_display_id, network, charge?) do
    state =
      state
      |> Spellcasting.cancel()
      |> Spellcasting.cancel_auto_repeat()
      |> CompanionOwner.suspend()

    destination_node_id = List.last(itinerary.paths).destination_node_id
    destination = TaxiNetwork.node(network, destination_node_id)
    token = make_ref()
    now = Time.now()
    itinerary = if charge?, do: itinerary, else: %{itinerary | total_cost: 0}
    {character, effects} = TaxiLogic.start(state.character, itinerary, destination, mount_display_id, token, now)

    state =
      %{state | character: character}
      |> PlayerServer.maybe_broadcast_update()

    character = EventSink.emit(state.character, effects)
    state = schedule_progress(%{state | character: character}, token, now)
    CharacterStore.put(character)
    state
  end

  defp schedule_progress(state, token, now) do
    delay = max(Movement.next_spatial_update_delay(state.character, now), 1)
    ref = Process.send_after(self(), {:taxi_progress, token}, delay)
    %{state | taxi_arrival_ref: ref}
  end

  defp cancel_arrival(%{taxi_arrival_ref: ref}) when is_reference(ref), do: Process.cancel_timer(ref)
  defp cancel_arrival(_state), do: :ok

  defp send_reply(reply) do
    Network.send_packet(%Message.SmsgActivatetaxireply{reply: reply})
  end

  defp reply_for(:no_such_path), do: @reply_no_such_path
  defp reply_for(:not_enough_money), do: @reply_not_enough_money
  defp reply_for(:invalid_flightmaster), do: @reply_no_vendor_nearby
  defp reply_for(:not_visited), do: @reply_not_visited
  defp reply_for(:player_busy), do: @reply_player_busy
  defp reply_for(:already_mounted), do: @reply_player_already_mounted
  defp reply_for(:shapeshifted), do: @reply_player_shapeshifted
  defp reply_for(:same_node), do: @reply_same_node
  defp reply_for(:not_standing), do: @reply_not_standing
  defp reply_for(:unspecified), do: @reply_unspecified

  defp discover(%{character: %Character{player: player} = character} = state, flightmaster_guid, node_id) do
    known = MapSet.put(player.taxi_nodes || MapSet.new(), node_id)
    character = %{character | player: %{player | taxi_nodes: known}}
    CharacterStore.put(character)
    Network.send_packet(%Message.SmsgNewTaxiPath{})
    Network.send_packet(%Message.SmsgTaxinodeStatus{guid: flightmaster_guid, known?: true})
    %{state | character: character}
  end

  defp send_menu(%Character{player: player}, flightmaster_guid, node_id, network) do
    Network.send_packet(%Message.SmsgShowtaxinodes{
      guid: flightmaster_guid,
      nearest_node: node_id,
      nodes: TaxiNetwork.mask(network, player.taxi_nodes || MapSet.new())
    })
  end

  defp flightmaster_node(
         %Character{unit: unit, internal: %{world: world}, movement_block: %{position: player_position}} = character,
         guid,
         network
       )
       when is_integer(guid) do
    with :mob <- Guid.entity_type(guid),
         %{npc_flags: npc_flags, alive?: true} <- Metadata.query(guid, [:npc_flags, :alive?]),
         true <- (npc_flags &&& @flightmaster_flag) != 0,
         true <- Reputation.can_interact?(character, guid),
         {^world, x, y, z} <- World.position(guid),
         true <- SpatialHash.distance(xyz(player_position), {x, y, z}) <= @interaction_distance,
         %Node{} = node <- TaxiNetwork.nearest_node(network, world.map_id, {x, y, z}, team_for_race(unit.race)) do
      {:ok, node}
    else
      _invalid -> {:error, :invalid_flightmaster}
    end
  end

  defp flightmaster_node(%Character{}, _guid, _network), do: {:error, :invalid_flightmaster}

  defp xyz({x, y, z, _orientation}), do: {x, y, z}
end
