defmodule ThistleTea.Game.World.Entity.Player.Rest do
  @moduledoc """
  Boundary for rest-state transitions: entering tavern area triggers,
  entering/leaving capital city zones, and clearing tavern rest once the
  player moves out of the trigger. All pool math lives in `Core.Player.Rest`;
  this module persists and broadcasts the transition.
  """
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.DB.DBC
  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Player.Rest, as: RestCore
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Entity.Player, as: PlayerServer
  alias ThistleTea.Game.World.Entity.Player.TickScheduler
  alias ThistleTea.Game.World.Loader.AreaTrigger, as: AreaTriggerLoader

  @area_flag_capital 0x100
  @area_team_alliance 2
  @area_team_horde 4
  @alliance_races [1, 3, 4, 7]
  @horde_races [2, 5, 6, 8]

  def restore(%Character{} = character, now \\ Time.now()) do
    character |> RestCore.restore(now) |> CharacterStore.put()
  end

  def logout(%{character: %Character{} = character} = state, now \\ Time.now()) do
    %{state | character: RestCore.logout(character, now)}
  end

  def enter_tavern(%{character: %Character{} = character} = state, trigger_id) do
    case RestCore.rest_type(character) do
      :city -> state
      {:tavern, ^trigger_id} -> state
      _other -> apply_transition(state, RestCore.start(character, {:tavern, trigger_id}, Time.now()))
    end
  end

  def update_zone(%{character: %Character{} = character} = state, zone_id) do
    case evaluate_zone(character, zone_id) do
      ^character -> state
      changed -> apply_transition(state, changed)
    end
  end

  def evaluate_zone(%Character{} = character, zone_id) do
    rest_capital? = friendly_capital?(character, zone_id)

    cond do
      rest_capital? and RestCore.rest_type(character) != :city ->
        RestCore.start(character, :city, Time.now())

      not rest_capital? and RestCore.rest_type(character) == :city ->
        RestCore.stop(character, Time.now())

      true ->
        character
    end
  end

  def default_zone(map_id) when is_integer(map_id) do
    case DBC.get(DBC.MapEntry, map_id) do
      %DBC.MapEntry{area_table: zone_id} when is_integer(zone_id) and zone_id > 0 -> zone_id
      _missing -> nil
    end
  end

  def default_zone(_map_id), do: nil

  def check_tavern_exit(%{character: %Character{} = character} = state) do
    with {:tavern, trigger_id} <- RestCore.rest_type(character),
         false <- inside_trigger?(character, trigger_id) do
      apply_transition(state, RestCore.stop(character, Time.now()))
    else
      _still_resting -> state
    end
  end

  defp inside_trigger?(%Character{} = character, trigger_id) do
    {x, y, z, _o} = character.movement_block.position

    case AreaTriggerLoader.get(trigger_id) do
      %{} = trigger -> AreaTriggerLoader.inside?(trigger, character.internal.world.map_id, {x, y, z})
      nil -> false
    end
  end

  defp friendly_capital?(%Character{unit: %{race: race}}, zone_id) when is_integer(zone_id) and zone_id > 0 do
    case DBC.get(DBC.AreaTable, zone_id) do
      %DBC.AreaTable{flags: flags, faction_group: faction_group} when is_integer(flags) ->
        (flags &&& @area_flag_capital) != 0 and friendly_area_team?(race, faction_group)

      _missing ->
        false
    end
  end

  defp friendly_capital?(%Character{}, _zone_id), do: false

  defp friendly_area_team?(race, @area_team_alliance), do: race in @alliance_races
  defp friendly_area_team?(race, @area_team_horde), do: race in @horde_races
  defp friendly_area_team?(_race, _area_team), do: true

  defp apply_transition(state, %Character{} = character) do
    CharacterStore.put(character)

    %{state | character: Entity.mark_broadcast_update(character)}
    |> PlayerServer.maybe_broadcast_update()
    |> TickScheduler.ensure_scheduled()
  end
end
