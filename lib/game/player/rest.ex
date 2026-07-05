defmodule ThistleTea.Game.Player.Rest do
  @moduledoc """
  Boundary for rest-state transitions: entering tavern area triggers,
  entering/leaving capital city zones, and clearing tavern rest once the
  player moves out of the trigger. All pool math lives in `Logic.Rest`;
  this module persists and broadcasts the transition.
  """
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.DBC
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Rest, as: RestLogic
  alias ThistleTea.Game.Network.Server
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Loader.AreaTrigger, as: AreaTriggerLoader

  @area_flag_capital 0x100

  def enter_tavern(%{character: %Character{} = character} = state, trigger_id) do
    case RestLogic.rest_type(character) do
      :city -> state
      {:tavern, ^trigger_id} -> state
      _other -> apply_transition(state, RestLogic.start(character, {:tavern, trigger_id}, Time.now()))
    end
  end

  def update_zone(%{character: %Character{} = character} = state, zone_id) do
    capital? = capital?(zone_id)

    cond do
      capital? and RestLogic.rest_type(character) != :city ->
        apply_transition(state, RestLogic.start(character, :city, Time.now()))

      not capital? and RestLogic.rest_type(character) == :city ->
        apply_transition(state, RestLogic.stop(character, Time.now()))

      true ->
        state
    end
  end

  def check_tavern_exit(%{character: %Character{} = character} = state) do
    with {:tavern, trigger_id} <- RestLogic.rest_type(character),
         false <- inside_trigger?(character, trigger_id) do
      apply_transition(state, RestLogic.stop(character, Time.now()))
    else
      _still_resting -> state
    end
  end

  defp inside_trigger?(%Character{} = character, trigger_id) do
    {x, y, z, _o} = character.movement_block.position

    case AreaTriggerLoader.get(trigger_id) do
      %{} = trigger -> AreaTriggerLoader.inside?(trigger, character.internal.map, {x, y, z})
      nil -> false
    end
  end

  defp capital?(zone_id) when is_integer(zone_id) and zone_id > 0 do
    case DBC.get(AreaTable, zone_id) do
      %AreaTable{flags: flags} when is_integer(flags) -> (flags &&& @area_flag_capital) != 0
      _missing -> false
    end
  end

  defp capital?(_zone_id), do: false

  defp apply_transition(state, %Character{} = character) do
    CharacterStore.put(character)
    Server.maybe_broadcast_update(%{state | character: Core.mark_broadcast_update(character)})
  end
end
