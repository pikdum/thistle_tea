defmodule ThistleTea.Game.Player.OutdoorPvp do
  @moduledoc "Player-owned resource delivery, zone projections, and carrier lifecycle cleanup."

  alias ThistleTea.Game.Battleground
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Silithyst
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.World.System.OutdoorPvp, as: OutdoorPvpSystem

  def refresh(%{ready: true, character: %Character{} = character} = state) do
    {x, y, z, _orientation} = character.movement_block.position

    zone =
      case Pathfinding.get_zone_and_area(character.internal.world.map_id, {x, y, z}) do
        {zone, _area} -> zone
        _ -> nil
      end

    refresh(state, zone)
  end

  def refresh(state), do: state

  def refresh(%{character: %Character{} = character} = state, zone) do
    team = Battleground.team_for_race(character.unit.race)
    context = OutdoorPvpSystem.sync(state.guid, character.internal.world, zone, team)

    Enum.each(context.states, fn {id, value} ->
      Network.send_packet(%Message.SmsgUpdateWorldState{state: id, value: value})
    end)

    {character, effects} = sync_favor(character, context.favor?, Time.now())
    %{state | character: EventSink.emit(character, effects)}
  end

  def area_trigger(%{character: %Character{} = character} = state, trigger_id) do
    case Silithyst.turn_in(character, trigger_id, Time.now()) do
      {:ok, updated, team, token, effects} ->
        OutdoorPvpSystem.sync(state.guid, character.internal.world, 1377, team)

        case OutdoorPvpSystem.contribute(state.guid, character.internal.world, team, token) do
          {:ok, _outcome} ->
            state = %{state | character: EventSink.emit(updated, effects)}
            Quests.credit_kill_entry(state, Silithyst.credit_entry(team), 0)

          {:error, _reason} ->
            state
        end

      :unavailable ->
        state
    end
  end

  def leave(%{character: %Character{} = character} = state) do
    OutdoorPvpSystem.leave(state.guid)

    {character, effects} =
      Aura.remove_spells(character, [Silithyst.carrier_spell(), Silithyst.favor_spell()], Time.now())

    %{state | character: EventSink.emit(character, effects)}
  end

  def leave(state), do: state

  defp sync_favor(character, true, now) do
    if Aura.has_spell?(character, Silithyst.favor_spell()) do
      {character, []}
    else
      case SpellLoader.cached(Silithyst.favor_spell()) do
        nil -> {character, []}
        spell -> Aura.apply_spell(character, character.object.guid, character.unit.level || 1, spell, now)
      end
    end
  end

  defp sync_favor(character, false, now), do: Aura.remove_spells(character, [Silithyst.favor_spell()], now)
end
