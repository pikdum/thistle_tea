defmodule ThistleTea.Game.Entity.Logic.GameObjectActions do
  @moduledoc "Pure object activation, flag changes, and revision-checked door restoration."

  import Bitwise, only: [&&&: 2, |||: 2, bnot: 1]

  alias ThistleTea.Game.Entity.Data.Component.Internal.ObjectAction
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects

  def configuration(%GameObjectTemplate{type: type, data: data}, state) do
    delay = if type in [0, 1], do: div(Enum.at(data, 2, 0), 65_536) * 1_000, else: 0
    %ObjectAction{default_state: state, auto_close_ms: delay}
  end

  def apply(%GameObject{} = entity, action, user_guid) when action in [5, 8],
    do: Effects.enqueue(entity, %Effects.ActivateGameObject{user_guid: user_guid})

  def apply(%GameObject{} = entity, action, _user_guid) when action in 1..4,
    do: Effects.enqueue(entity, Effects.game_object_custom_animation(action - 1))

  def apply(%GameObject{} = entity, 6, _user_guid), do: lock(entity, false)
  def apply(%GameObject{} = entity, 7, _user_guid), do: lock(entity, true)
  def apply(%GameObject{} = entity, 9, _user_guid), do: entity |> activate() |> lock(false)
  def apply(%GameObject{} = entity, action, _user_guid) when action in [10, 13], do: reset(entity)
  def apply(%GameObject{} = entity, 12, _user_guid), do: activate(entity, true)

  def apply(%GameObject{} = entity, 15, _user_guid),
    do: Effects.enqueue(entity, %Effects.RemoveSelf{respawn_delay_ms: nil})

  def apply(%GameObject{} = entity, 16, _user_guid), do: flag(entity, 0x10, true)
  def apply(%GameObject{} = entity, 17, _user_guid), do: flag(entity, 0x10, false)
  def apply(%GameObject{} = entity, 18, _user_guid), do: entity |> reset() |> lock(true)
  def apply(%GameObject{} = entity, _action, _user_guid), do: entity

  def usable?(%GameObject{game_object: object}), do: ((object.flags || 0) &&& 0x10) == 0

  def set_state(%GameObject{} = entity, state) do
    action = %{entity.internal.object_action | revision: entity.internal.object_action.revision + 1}

    %{entity | game_object: %{entity.game_object | state: state}, internal: %{entity.internal | object_action: action}}
    |> Core.mark_broadcast_update()
  end

  def activate(entity, alternative? \\ false)

  def activate(%GameObject{internal: %{object_action: %ObjectAction{active?: true}}} = entity, _alternative?),
    do: entity

  def activate(%GameObject{internal: %{object_action: action}} = entity, alternative?) do
    next = if entity.game_object.state == 1, do: if(alternative?, do: 2, else: 0), else: 1
    transition(entity, next, %{action | active?: true}, action.auto_close_ms, action.default_state)
  end

  def reset(%GameObject{internal: %{object_action: %ObjectAction{active?: false}}} = entity), do: entity

  def reset(%GameObject{internal: %{object_action: action}} = entity),
    do: transition(entity, action.default_state, %{action | active?: false}, 0, action.default_state)

  def operate(%GameObject{} = entity, operation, delay_ms) do
    action = entity.internal.object_action
    previous = entity.game_object.state
    next = state(operation, previous, action.default_state)
    active? = operation in [:open, :destroy]
    transition(entity, next, %{action | active?: active?}, delay_ms, previous)
  end

  def restore(
        %GameObject{internal: %{object_action: %ObjectAction{revision: revision} = action}} = entity,
        revision,
        state
      ), do: transition(entity, state, %{action | active?: false}, 0, state)

  def restore(%GameObject{} = entity, _revision, _state), do: entity

  defp state(:open, 1, _default), do: 0
  defp state(:open, current, _default), do: current
  defp state(:close, 0, _default), do: 1
  defp state(:close, current, _default), do: current
  defp state(:destroy, _current, _default), do: 2
  defp state(:reset, _current, default), do: default

  defp transition(entity, state, action, delay, restore_state) do
    action = %{action | revision: action.revision + 1}
    object = %{entity.game_object | state: state}
    entity = %{entity | game_object: object, internal: %{entity.internal | object_action: action}}
    entity = entity |> flag(0x1, action.active?) |> Core.mark_broadcast_update()

    if delay > 0 do
      Effects.enqueue(entity, %Effects.RestoreGameObject{
        revision: action.revision,
        state: restore_state,
        delay_ms: delay
      })
    else
      entity
    end
  end

  defp lock(entity, locked?) do
    action = %{entity.internal.object_action | lock_override: locked?}
    entity = %{entity | internal: %{entity.internal | object_action: action}}
    flag(entity, 0x2, locked?)
  end

  defp flag(entity, flag, enabled?) do
    flags = entity.game_object.flags || 0
    flags = if enabled?, do: flags ||| flag, else: flags &&& bnot(flag)
    %{entity | game_object: %{entity.game_object | flags: flags}} |> Core.mark_broadcast_update()
  end
end
