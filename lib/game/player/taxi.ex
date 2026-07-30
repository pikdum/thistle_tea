defmodule ThistleTea.Game.Player.Taxi do
  @moduledoc """
  Player taxi boundary for flight-master interaction, node discovery, and
  route activation.
  """
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Taxi.Network, as: TaxiNetwork
  alias ThistleTea.Game.Entity.Data.Taxi.Node
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Loader.Taxi, as: TaxiLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash

  @flightmaster_flag 0x00000008
  @interaction_distance 5.0
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

  def activate(state, _flightmaster_guid, _node_ids, _network), do: state

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
         %Character{unit: unit, internal: %{world: world}, movement_block: %{position: player_position}},
         guid,
         network
       )
       when is_integer(guid) do
    with :mob <- Guid.entity_type(guid),
         %{npc_flags: npc_flags, alive?: true} <- Metadata.query(guid, [:npc_flags, :alive?]),
         true <- (npc_flags &&& @flightmaster_flag) != 0,
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
