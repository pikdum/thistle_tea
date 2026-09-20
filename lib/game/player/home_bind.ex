defmodule ThistleTea.Game.Player.HomeBind do
  @moduledoc """
  Innkeeper confirmation, live interaction validation, and home-location updates.
  The bind spell returns through the player's owner before changing the home.
  """

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.HomeBind
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Reputation
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Loader.MapTemplate
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.WorldRef

  @innkeeper_flag 0x00000080
  @bind_spell 3286

  def confirm(%State{ready: true, character: %Character{} = character} = state, guid) do
    if valid_innkeeper?(character, guid) do
      Network.send_packet(%Message.SmsgGossipComplete{})
      Network.send_packet(%Message.SmsgBinderConfirm{guid: guid})
      %{state | gossip_menu_options: []}
    else
      state
    end
  end

  def confirm(state, _guid), do: state

  def activate(%State{ready: true, character: %Character{} = character} = state, guid) do
    if valid_innkeeper?(character, guid) do
      Entity.trigger_spell(guid, @bind_spell, character.object.guid)
      Network.send_packet(%Message.SmsgGossipComplete{})
      %{state | gossip_menu_options: []}
    else
      state
    end
  end

  def activate(state, _guid), do: state

  def complete(state, guid, opts \\ [])

  def complete(%State{ready: true, character: %Character{} = character} = state, guid, opts) do
    if valid_innkeeper?(character, guid) do
      {x, y, z, _orientation} = character.movement_block.position
      map_id = character.internal.world.map_id
      area_lookup = Keyword.get(opts, :area_lookup, &Pathfinding.get_zone_and_area/2)

      area_id =
        case area_lookup.(map_id, {x, y, z}) do
          {_zone_id, area_id} when is_integer(area_id) and area_id > 0 -> area_id
          _unknown -> character.internal.area
        end

      home = %HomeBind{map_id: map_id, area_id: area_id, position: {x, y, z}}
      character = %{character | internal: %{character.internal | home_bind: home}}
      CharacterStore.put(character)
      send_update(character)
      Network.send_packet(%Message.SmsgPlayerbound{guid: guid, area: area_id})
      %{state | character: character}
    else
      state
    end
  end

  def complete(state, _guid, _opts), do: state

  def send_update(%Character{internal: %{home_bind: %HomeBind{} = home}}) do
    {x, y, z} = home.position
    Network.send_packet(%Message.SmsgBindpointupdate{x: x, y: y, z: z, map: home.map_id, area: home.area_id})
  end

  def send_update(%Character{}), do: :ok

  def valid_innkeeper?(%Character{} = character, guid) do
    with true <- Death.alive?(character),
         %WorldRef{map_id: map_id, instance_id: nil} = world <- character.internal.world,
         false <- MapTemplate.dungeon?(map_id) or MapTemplate.battleground?(map_id),
         :mob <- Guid.entity_type(guid),
         %{alive?: true, npc_flags: flags} when is_integer(flags) <- Metadata.query(guid, [:alive?, :npc_flags]),
         true <- (flags &&& @innkeeper_flag) != 0,
         true <- Reputation.can_interact?(character, guid),
         {^world, _x, _y, _z} <- World.position(guid),
         distance when is_number(distance) and distance <= 5.0 <- World.distance_between(character, guid) do
      true
    else
      _invalid -> false
    end
  end
end
