defmodule ThistleTea.Game.Player.Exploration do
  @moduledoc """
  Player exploration boundary: resolves terrain areas, applies first-discovery
  state and XP, persists the character, and emits client updates.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Exploration, as: ExplorationLogic
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Party.Notifier, as: PartyNotifier
  alias ThistleTea.Game.Player.Stats
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Loader.Exploration, as: ExplorationLoader
  alias ThistleTea.Game.World.Pathfinding

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
            unit: %Unit{health: health},
            internal: %{world: world},
            movement_block: %MovementBlock{position: {x, y, z, _orientation}}
          }
        } = state
      )
      when health > 0 do
    case Pathfinding.get_zone_and_area(world.map_id, {x, y, z}) do
      {_zone_id, area_id} -> discover_area(state, area_id)
      _unknown -> state
    end
  end

  def check_current(state), do: state

  def discover_area(%{character: %Character{} = character} = state, area_id) do
    with %AreaTable{area_bit: area_bit, exploration_level: area_level} <- ExplorationLoader.area(area_id),
         {:ok, character} <- ExplorationLogic.discover(character, area_bit) do
      xp = ExplorationLogic.experience(character.unit.level, area_level, @max_level, &ExplorationLoader.base_xp/1)
      {character, level_ups} = if xp > 0, do: Stats.gain_xp(character, xp), else: {character, []}
      CharacterStore.put(character)
      Network.send_packet(Core.update_object(character, :values))
      Network.send_packet(%Message.SmsgExplorationExperience{area_id: area_id, experience: xp})
      Enum.each(level_ups, &Network.send_packet(struct(Message.SmsgLevelupInfo, &1)))

      if level_ups != [] do
        PartyNotifier.broadcast_stats(state.guid, character)
      end

      %{state | character: character}
    else
      _unknown_or_explored -> state
    end
  end

  def unlock_all(%{character: %Character{} = character} = state) do
    character = ExplorationLogic.unlock_all(character)
    CharacterStore.put(character)
    Network.send_packet(Core.update_object(character, :values))
    %{state | character: character}
  end
end
