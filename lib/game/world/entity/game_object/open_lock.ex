defmodule ThistleTea.Game.World.Entity.GameObject.OpenLock do
  @moduledoc """
  Serializes object opening and records successful skill gains for this spawn.
  Loot access is granted only after an admitted, successful attempt.
  """
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Core.Entity.Component.Internal.Gathering, as: GatheringState
  alias ThistleTea.Game.Core.Entity.Component.Internal.Trap
  alias ThistleTea.Game.Core.Entity.GameObject
  alias ThistleTea.Game.Core.Loot
  alias ThistleTea.Game.Core.Loot.Actor
  alias ThistleTea.Game.Core.Loot.LootSession
  alias ThistleTea.Game.Core.Profession.Gathering
  alias ThistleTea.Game.Core.Profession.OpenLock
  alias ThistleTea.Game.World.Entity.GameObject.Chest

  def open(%GameObject{} = state, %Actor{} = actor, %OpenLock{} = opened, gain?, opts \\ []) do
    with :ok <- validate_open(state, actor, opened),
         true <- successful_attempt?(opened, opts) do
      gathering = state.internal.gathering
      gained? = gain? and not MapSet.member?(gathering.skilled_players, actor.guid)
      players = if gained?, do: MapSet.put(gathering.skilled_players, actor.guid), else: gathering.skilled_players
      gathering = %{gathering | opened_by: Map.put(gathering.opened_by, actor.guid, opened), skilled_players: players}
      updated = %{state | internal: %{state.internal | gathering: gathering}}

      case content(updated, actor, opened) do
        {{:ok, content}, updated} ->
          {{:ok, content, gained?}, monitor_viewer(updated, actor, content, opts)}

        {{:error, :nothing_to_take}, updated} ->
          {{:ok, %Loot{}, gained?}, monitor_viewer(updated, actor, %Loot{}, opts)}

        {error, _changed} ->
          {error, state}
      end
    else
      false -> {{:error, :try_again}, state}
      error -> {error, state}
    end
  end

  defp monitor_viewer(state, actor, %Loot{}, opts) do
    case Keyword.get(opts, :owner_pid) do
      pid when is_pid(pid) ->
        gathering = state.internal.gathering
        monitors = Map.put(gathering.viewer_monitors, Process.monitor(pid), actor)
        %{state | internal: %{state.internal | gathering: %{gathering | viewer_monitors: monitors}}}

      _ ->
        state
    end
  end

  defp monitor_viewer(state, _actor, _content, _opts), do: state

  defp content(%GameObject{internal: %{trap: %Trap{}}} = state, _actor, %OpenLock{lock_type: 4}),
    do: {{:ok, :disarmed}, state}

  defp content(state, actor, _opened) do
    if Chest.lootable?(state), do: Chest.view(state, actor), else: {{:ok, :activate}, state}
  end

  defp validate_open(%GameObject{internal: %{gathering: %GatheringState{lock_id: id}}} = state, actor, opened) do
    cond do
      id != opened.lock_id or removed?(state) -> {:error, :bad_targets}
      not Actor.within?(actor, 5.0) -> {:error, :out_of_range}
      ((state.game_object.flags || 0) &&& 0x11) != 0 or in_use?(state) -> {:error, :chest_in_use}
      true -> :ok
    end
  end

  defp validate_open(_state, _actor, _opened), do: {:error, :bad_targets}

  defp removed?(%GameObject{internal: %{trap: %Trap{depleted?: true}}}), do: true
  defp removed?(%GameObject{internal: %{loot: %{corpse_removed?: true}}}), do: true
  defp removed?(_state), do: false

  defp successful_attempt?(%OpenLock{skill_id: id, value: value, required: required}, opts)
       when id in [182, 186, 633] do
    roll = Keyword.get_lazy(opts, :attempt_roll, fn -> value - 26 + :rand.uniform(63) end)
    Gathering.attempt?(id, value, required, roll)
  end

  defp successful_attempt?(_opened, _opts), do: true

  defp in_use?(%GameObject{internal: %{loot: %{session: %LootSession{} = session}}}) do
    LootSession.viewers(session) != [] or LootSession.pending?(session)
  end

  defp in_use?(_state), do: false
end
