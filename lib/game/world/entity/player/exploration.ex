defmodule ThistleTea.Game.World.Entity.Player.Exploration do
  @moduledoc """
  Player exploration boundary: resolves terrain areas, applies first-discovery
  state and XP, persists the character, and emits client updates.
  """
  alias ThistleTea.DB.DBC
  alias ThistleTea.Game.Core.Death
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Player.Exploration, as: ExplorationCore
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Entity.Player.OutdoorPvp
  alias ThistleTea.Game.World.Entity.Player.Pvp
  alias ThistleTea.Game.World.Entity.Player.Rest
  alias ThistleTea.Game.World.Entity.Player.Stats
  alias ThistleTea.Game.World.Entity.Player.Weather
  alias ThistleTea.Game.World.Loader.Exploration, as: ExplorationLoader
  alias ThistleTea.Game.World.Outbound
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.World.System.Party.Notifier, as: PartyNotifier

  @max_level 60
  @movement_check_interval_ms 1_000

  def check_movement(state, now \\ Time.now())

  def check_movement(%{next_exploration_check_at: next_check} = state, now)
      when is_integer(next_check) and next_check > now, do: state

  def check_movement(state, now) when is_integer(now) do
    state
    |> Map.put(:next_exploration_check_at, now + @movement_check_interval_ms)
    |> check_current()
  end

  def check_current(
        %{
          ready: true,
          character: %Character{
            internal: %{world: world},
            movement_block: %MovementBlock{position: {x, y, z, _orientation}}
          }
        } = state
      ) do
    case Pathfinding.get_zone_and_area(world.map_id, {x, y, z}) do
      {zone_id, area_id} ->
        state = Weather.refresh(state, zone_id)
        state = OutdoorPvp.update_zone(state, zone_id)
        state = Pvp.update_territory(state, zone_id, area_id)
        discover_area(state, area_id)

      _unknown ->
        zone = Rest.default_zone(world.map_id)

        state
        |> Weather.refresh(zone)
        |> OutdoorPvp.update_zone(zone)
        |> Pvp.update_territory(zone, state.character.internal.area)
    end
  end

  def check_current(state), do: state

  def discover_area(%{character: %Character{} = character} = state, area_id) do
    with true <- Death.alive?(character),
         %DBC.AreaTable{area_bit: area_bit, exploration_level: area_level} <- ExplorationLoader.area(area_id),
         {:ok, character} <- ExplorationCore.discover(character, area_bit) do
      xp = ExplorationCore.experience(character.unit.level, area_level, @max_level, &ExplorationLoader.base_xp/1)
      {character, level_ups} = if xp > 0, do: Stats.gain_xp(character, xp), else: {character, []}
      CharacterStore.put(character)
      Outbound.send_packet(UpdateObject.from_entity(character, :values))
      Outbound.send_packet(%Message.SmsgExplorationExperience{area_id: area_id, experience: xp})
      Enum.each(level_ups, &Outbound.send_packet(struct(Message.SmsgLevelupInfo, &1)))

      if level_ups != [] do
        PartyNotifier.broadcast_stats(state.guid, character)
      end

      %{state | character: character}
    else
      _unknown_or_explored -> state
    end
  end

  def unlock_all(%{character: %Character{} = character} = state) do
    character = ExplorationCore.unlock_all(character)
    CharacterStore.put(character)
    Outbound.send_packet(UpdateObject.from_entity(character, :values))
    %{state | character: character}
  end
end
