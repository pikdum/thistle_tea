defmodule ThistleTea.Game.Entity.Logic.TemporaryFaction do
  @moduledoc """
  Owns script-driven creature faction overrides and their VMangos restoration
  policies.
  """

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Core

  @restore_respawn 0x01
  @restore_combat_stop 0x02
  @restore_reach_home 0x04

  def set(%Mob{internal: %Internal{creature: %Creature{} = creature} = internal} = state, faction, flags)
      when is_integer(faction) and faction > 0 and is_integer(flags) do
    original = creature.script_faction_original || state.unit.faction_template

    creature = %{
      creature
      | script_faction_original: original,
        script_faction_value: faction,
        script_faction_flags: flags
    }

    %{state | unit: %{state.unit | faction_template: faction}, internal: %{internal | creature: creature}}
    |> Core.mark_broadcast_update()
  end

  def set(%Mob{} = state, _faction, _flags), do: state

  def clear(
        %Mob{internal: %Internal{creature: %Creature{script_faction_original: original} = creature} = internal} = state
      )
      when is_integer(original) do
    creature = clear_tracking(creature)

    %{state | unit: %{state.unit | faction_template: original}, internal: %{internal | creature: creature}}
    |> Core.mark_broadcast_update()
  end

  def clear(%Mob{} = state), do: state

  def restore(%Mob{} = state, reason) when reason in [:respawn, :combat_stop, :reach_home] do
    if restore?(state, reason), do: clear(state), else: state
  end

  def after_respawn(%Mob{internal: %Internal{creature: %Creature{} = creature} = internal} = state) do
    if tracked?(creature) do
      if (creature.script_faction_flags &&& @restore_respawn) == 0 do
        %{state | unit: %{state.unit | faction_template: creature.script_faction_value}}
      else
        %{state | internal: %{internal | creature: clear_tracking(creature)}}
      end
    else
      state
    end
  end

  def after_respawn(%Mob{} = state), do: state

  defp restore?(%Mob{internal: %Internal{creature: %Creature{script_faction_flags: flags}}}, reason)
       when is_integer(flags) do
    (flags &&& restore_flag(reason)) != 0
  end

  defp restore?(%Mob{}, _reason), do: false

  defp restore_flag(:respawn), do: @restore_respawn
  defp restore_flag(:combat_stop), do: @restore_combat_stop
  defp restore_flag(:reach_home), do: @restore_reach_home

  defp tracked?(%Creature{} = creature) do
    is_integer(creature.script_faction_original) and
      is_integer(creature.script_faction_value) and
      is_integer(creature.script_faction_flags)
  end

  defp clear_tracking(%Creature{} = creature) do
    %{
      creature
      | script_faction_original: nil,
        script_faction_value: nil,
        script_faction_flags: nil
    }
  end
end
