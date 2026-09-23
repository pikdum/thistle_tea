defmodule ThistleTea.Game.Player.Corpses do
  @moduledoc "Spirit release, corpse admission checks, and recovery countdown projection."

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Corpse
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.CorpseReclaim
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.MovementControl
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Graveyard
  alias ThistleTea.Game.World.Loader.MapTemplate
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.System.Battleground
  alias ThistleTea.Game.World.Visibility

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
    ghost_spells = character |> Death.ghost_spell_ids() |> Enum.map(&SpellLoader.load/1) |> Enum.reject(&is_nil/1)
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
    case Graveyard.closest(map_id, position, team) do
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
