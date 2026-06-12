defmodule ThistleTea.Game.Network.PlayerTick do
  @moduledoc """
  Decides whether a player needs behavior-tree ticking (casting, combat,
  auras, regen) and schedules the next tick on the network handler only when
  needed.
  """
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Regen
  alias ThistleTea.Game.Spell.Cast

  def needs_tick?(%{internal: %Internal{casting: %Cast{}}}), do: true

  def needs_tick?(%{internal: %Internal{in_combat: true}, unit: %Unit{target: target}})
      when is_integer(target) and target > 0 do
    true
  end

  def needs_tick?(%{unit: %Unit{auras: [_ | _]}}), do: true

  def needs_tick?(character), do: Regen.needs_regen?(character)

  def ensure_scheduled(%{character: character} = state) do
    case Map.get(state, :player_tick_ref) do
      ref when is_reference(ref) ->
        state

      _ ->
        if needs_tick?(character) do
          ref = Process.send_after(self(), :player_tick, 0)
          Map.put(state, :player_tick_ref, ref)
        else
          state
        end
    end
  end

  def ensure_scheduled(state), do: state

  def schedule_now(state) do
    case Map.get(state, :player_tick_ref) do
      ref when is_reference(ref) -> Process.cancel_timer(ref)
      _ -> :ok
    end

    ref = Process.send_after(self(), :player_tick, 0)
    Map.put(state, :player_tick_ref, ref)
  end
end
