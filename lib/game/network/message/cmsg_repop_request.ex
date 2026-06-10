defmodule ThistleTea.Game.Network.Message.CmsgRepopRequest do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_REPOP_REQUEST

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Corpse
  alias ThistleTea.Game.Entity.Data.Item, as: DataItem
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Graveyard, as: GraveyardLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Visibility

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, %{ready: true, character: %Character{} = character} = state) do
    if Core.dead?(character) and not Death.ghost?(character) do
      release_spirit(state, character)
    else
      state
    end
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(_payload) do
    %__MODULE__{}
  end

  defp release_spirit(state, character) do
    now = Time.now()
    spawn_corpse(character)

    ghost_spells =
      character
      |> Death.ghost_spell_ids()
      |> Enum.map(&SpellLoader.load/1)
      |> Enum.reject(&is_nil/1)

    {character, events} = Death.release_spirit(character, ghost_spells, now)
    character = EventSink.emit(character, events)

    update = Core.update_object(character, :values)
    Network.send_packet(update)
    World.broadcast_packet(update, character, include_self?: false)
    Metadata.update(state.guid, %{alive?: false, ghost?: true})

    Network.send_packet(%Message.SmsgCorpseReclaimDelay{delay_ms: Death.reclaim_delay_ms()})

    character = clear_broadcast_flag(character)
    state = %{state | character: character}

    Visibility.notify_visibility_changed(character)
    state = Visibility.resync_player(state)

    teleport_to_graveyard(character)

    state
  end

  def spawn_corpse(character) do
    corpse_guid = Corpse.guid_for(character.object.guid)
    World.stop_entity(corpse_guid)

    character
    |> Corpse.build(equipped_templates(character))
    |> World.start_entity()
  end

  defp equipped_templates(character) do
    Inventory.slots()
    |> Enum.map(fn field ->
      with guid when is_integer(guid) and guid > 0 <- Map.get(character.player, field),
           %DataItem{} = item <- ItemStore.get(guid) do
        DataItem.template(item)
      else
        _ -> nil
      end
    end)
  end

  defp teleport_to_graveyard(character) do
    %{internal: %Internal{map: map}, movement_block: %MovementBlock{position: {x, y, z, _o}}} = character
    team = GraveyardLoader.team_for_race(character.unit.race)

    case GraveyardLoader.closest(map, {x, y, z}, team) do
      %{map: graveyard_map, position: {gx, gy, gz}} ->
        GenServer.cast(self(), {:start_teleport, gx, gy, gz, graveyard_map})

      _ ->
        :ok
    end
  end

  defp clear_broadcast_flag(%Character{internal: %Internal{} = internal} = character) do
    %{character | internal: %{internal | broadcast_update?: false}}
  end
end
