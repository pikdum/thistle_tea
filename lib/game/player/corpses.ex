defmodule ThistleTea.Game.Player.Corpses do
  @moduledoc "Spirit release, corpse admission checks, and recovery countdown projection."

  alias ThistleTea.Game.Battleground.Resurrection, as: BattlegroundResurrection
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Corpse
  alias ThistleTea.Game.Entity.Data.Dungeon
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.CorpseReclaim
  alias ThistleTea.Game.Entity.Logic.CorpseTravel
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.MovementControl
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Graveyards
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.AreaTrigger
  alias ThistleTea.Game.World.Loader.Graveyard
  alias ThistleTea.Game.World.Loader.MapTemplate
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.World.System.Battleground
  alias ThistleTea.Game.World.Visibility
  alias ThistleTea.Game.WorldRef

  def restore(%Character{} = character) do
    missing_body? = is_nil(World.position(Corpse.guid_for(character.object.guid)))
    battleground? = MapTemplate.battleground?(character.internal.world.map_id)

    if Death.ghost?(character) and missing_body? and not battleground? do
      {character, _events} = Death.resurrect(character, 0.5, Time.now())
      %{character | internal: %{character.internal | broadcast_update?: false}}
    else
      character
    end
  end

  def query(%{ready: true, character: %Character{} = character} = state) do
    Network.send_packet(location(character))
    state
  end

  def query(state), do: state

  def location(%Character{} = character, height \\ &entrance_height/2) do
    case World.position(Corpse.guid_for(character.object.guid)) do
      {%WorldRef{map_id: corpse_map}, x, y, z} ->
        {map, position} =
          case CorpseTravel.entrance(corpse_map, character.internal.world.map_id, MapTemplate.dungeons()) do
            {map, ex, ey} -> {map, {ex, ey, height.(map, {ex, ey})}}
            nil -> {corpse_map, {x, y, z}}
          end

        %Message.MsgCorpseQueryResponse{map: map, position: position, corpse_map: corpse_map}

      _missing ->
        %Message.MsgCorpseQueryResponse{}
    end
  end

  def portal_destination(%{character: %Character{} = character}, teleport) do
    if not Death.alive?(character) and MapTemplate.dungeon?(teleport.target_map) do
      ghost_destination(character, teleport)
    else
      {:ok, teleport}
    end
  end

  def revive_for_map(%{character: %Character{} = character} = state, map_id) do
    with true <- Death.ghost?(character) and MapTemplate.dungeon?(map_id),
         true <- character.internal.world.map_id != map_id,
         corpse_guid = Corpse.guid_for(character.object.guid),
         {%WorldRef{map_id: ^map_id}, _, _, _} <- World.position(corpse_guid) do
      resurrect(state, corpse_guid, 0.5, Time.now())
    else
      _unrelated -> state
    end
  end

  defp ghost_destination(character, teleport) do
    dungeons = MapTemplate.dungeons()

    with {%WorldRef{map_id: corpse_map}, _, _, _} <- World.position(Corpse.guid_for(character.object.guid)),
         {:ok, ^corpse_map} <- CorpseTravel.destination(corpse_map, teleport.target_map, dungeons) do
      destination =
        if corpse_map == teleport.target_map, do: teleport, else: AreaTrigger.entrance(corpse_map) || teleport

      {:ok, destination}
    else
      _missing ->
        name =
          case Map.get(dungeons, teleport.target_map) do
            %Dungeon{name: name} when is_binary(name) -> name
            _missing -> "this dungeon"
          end

        {:error, "You cannot enter #{name} while in ghost form."}
    end
  end

  defp entrance_height(map, position), do: map |> Pathfinding.find_heights(position) |> Enum.max(fn -> 0.0 end)

  def release(%{ready: true, character: %Character{} = character} = state) do
    if Core.dead?(character) and not Death.ghost?(character), do: release_spirit(state, Time.now()), else: state
  end

  def release(state), do: state

  def reclaim(state, now \\ Time.now())

  def reclaim(%{ready: true, character: %Character{} = character} = state, now) do
    corpse_guid = Corpse.guid_for(state.guid)

    with true <- Death.ghost?(character),
         true <- CorpseReclaim.ready?(character.internal.corpse_reclaim, now),
         true <- corpse_in_range?(character, corpse_guid),
         {:ok, restore_percent} <- restore_percent(character) do
      resurrect(state, corpse_guid, restore_percent, now)
    else
      _invalid -> state
    end
  end

  def reclaim(state, _now), do: state

  def send_reclaim_delay(%Character{} = character, now \\ Time.now()) do
    remaining = CorpseReclaim.remaining_ms(character.internal.corpse_reclaim, now)

    if Death.ghost?(character) and remaining > 0 do
      Network.send_packet(%Message.SmsgCorpseReclaimDelay{delay_ms: remaining})
    end
  end

  defp release_spirit(%{character: character} = state, now) do
    character = CorpseReclaim.release(character, now)
    spawn_corpse(character)

    waiting_spells =
      if MapTemplate.battleground?(character.internal.world.map_id), do: [BattlegroundResurrection.spell_id()], else: []

    ghost_spells =
      (Death.ghost_spell_ids(character) ++ waiting_spells) |> Enum.map(&SpellLoader.load/1) |> Enum.reject(&is_nil/1)

    {character, events} = Death.release_spirit(character, ghost_spells, now)
    character = EventSink.emit(character, events)
    state = PlayerServer.maybe_broadcast_update(%{state | character: character})
    send_reclaim_delay(character, now)
    Visibility.notify_visibility_changed(state.character)
    state |> Visibility.resync_player() |> defer_graveyard_teleport()
  end

  defp spawn_corpse(character) do
    World.stop_entity(Corpse.guid_for(character.object.guid))
    character |> Corpse.build(equipped_templates(character)) |> World.start_entity()
  end

  defp equipped_templates(character) do
    Enum.map(Inventory.slots(), fn field ->
      position = {Inventory.bag_0(), Inventory.slot_index(field)}

      with guid when is_integer(guid) and guid > 0 <-
             Inventory.item_guid_at(character.player, position, &ItemStore.get/1),
           %Item{} = item <- ItemStore.get(guid) do
        Item.template(item)
      else
        _empty -> nil
      end
    end)
  end

  defp defer_graveyard_teleport(%{character: character} = state) do
    world = character.internal.world
    {x, y, z, _o} = character.movement_block.position
    team = Graveyard.team_for_race(character.unit.race)

    case Battleground.graveyard(world, character.object.guid) do
      {gx, gy, gz, _orientation} -> MovementControl.defer_repop(state, {gx, gy, gz, world})
      nil -> defer_open_world_graveyard(state, world.map_id, {x, y, z}, team)
    end
  end

  defp defer_open_world_graveyard(state, map_id, position, team) do
    case Graveyards.closest(map_id, position, team) do
      %{map: graveyard_map, position: {gx, gy, gz}} ->
        MovementControl.defer_repop(state, {gx, gy, gz, graveyard_map})

      _missing ->
        state
    end
  end

  defp corpse_in_range?(character, corpse_guid) do
    case World.distance_between(character, corpse_guid) do
      distance when is_number(distance) -> distance <= Death.corpse_reclaim_radius()
      _missing -> false
    end
  end

  defp restore_percent(%Character{internal: %{world: world}, object: %{guid: guid}}) do
    if MapTemplate.battleground?(world.map_id) do
      if Battleground.corpse_recovery_allowed?(world, guid),
        do: {:ok, 1.0},
        else: {:error, :battleground_inactive}
    else
      {:ok, 0.5}
    end
  end

  defp resurrect(%{character: character} = state, corpse_guid, restore_percent, now) do
    World.stop_entity(corpse_guid)
    {character, events} = Death.resurrect(character, restore_percent, now)
    character = EventSink.emit(character, events)
    state = PlayerServer.maybe_broadcast_update(%{state | character: character})
    Visibility.notify_visibility_changed(state.character)
    Visibility.resync_player(state)
  end
end
