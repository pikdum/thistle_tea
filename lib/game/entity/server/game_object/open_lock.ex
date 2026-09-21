defmodule ThistleTea.Game.Entity.Server.GameObject.OpenLock do
  @moduledoc """
  Serializes object opening and records successful skill gains for this spawn.
  Loot access is granted only after an admitted, successful attempt.
  """
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Component.Internal.Gathering, as: GatheringState
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Logic.Gathering
  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.Entity.Logic.Loot.Actor
  alias ThistleTea.Game.Entity.Logic.LootSession
  alias ThistleTea.Game.Entity.Logic.OpenLock
  alias ThistleTea.Game.Entity.Server.GameObject.Chest

  def open(%GameObject{} = state, %Actor{} = actor, %OpenLock{} = opened, gain?, opts \\ []) do
    with :ok <- validate_open(state, actor, opened),
         true <- successful_attempt?(opened, opts) do
      gathering = state.internal.gathering
      gained? = gain? and not MapSet.member?(gathering.skilled_players, actor.guid)
      players = if gained?, do: MapSet.put(gathering.skilled_players, actor.guid), else: gathering.skilled_players
      gathering = %{gathering | opened_by: Map.put(gathering.opened_by, actor.guid, opened), skilled_players: players}
      updated = %{state | internal: %{state.internal | gathering: gathering}}

      case content(updated, actor) do
        {{:ok, content}, updated} -> {{:ok, content, gained?}, updated}
        {{:error, :nothing_to_take}, updated} -> {{:ok, %Loot{}, gained?}, updated}
        {error, _changed} -> {error, state}
      end
    else
      false -> {{:error, :try_again}, state}
      error -> {error, state}
    end
  end

  defp content(state, actor) do
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
