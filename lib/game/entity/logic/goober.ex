defmodule ThistleTea.Game.Entity.Logic.Goober do
  @moduledoc "Pure admission and activation lifecycle for interactive quest objects."

  alias ThistleTea.Game.Entity.Data.Component.Internal.Goober
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.GameObjectActions
  alias ThistleTea.Game.Entity.Logic.QuestLog

  @custom_displays [2570, 3071, 3072, 3073, 3074, 4392, 4472, 4491, 6785, 6747, 6871]

  def configuration(%GameObjectTemplate{type: 10, data: data, display_id: display}) do
    auto_close_ms = div(Enum.at(data, 3, 0), 65_536) * 1_000

    %Goober{
      quest_id: Enum.at(data, 1, 0),
      event_id: Enum.at(data, 2, 0),
      auto_close_ms: auto_close_ms,
      custom_animation?: display in @custom_displays or (auto_close_ms > 0 and Enum.at(data, 4, 0) != 0),
      consumable?: Enum.at(data, 5, 0) != 0,
      cooldown_ms: max(Enum.at(data, 6, 0), 0) * 1_000,
      page_id: Enum.at(data, 7, 0),
      spell_id: Enum.at(data, 10, 0),
      gossip_id: Enum.at(data, 19, 0)
    }
  end

  def configuration(%GameObjectTemplate{}), do: nil

  def quest_allowed?(quest_log, quest_id, quest_exists?) do
    quest_id <= 0 or not quest_exists? or
      match?(%QuestLog.Entry{status: :incomplete}, QuestLog.get(quest_log || %{}, quest_id))
  end

  def use(%GameObject{internal: %{goober: %Goober{} = goober}} = entity, quest_allowed?, now) do
    cond do
      not GameObjectActions.usable?(entity) or goober.depleted? or entity.internal.object_action.active? ->
        {:unavailable, entity}

      is_integer(goober.ready_at) and now < goober.ready_at ->
        {:unavailable, entity}

      not quest_allowed? ->
        {:read_only, put_goober(entity, %{goober | ready_at: now + goober.cooldown_ms})}

      true ->
        {:activated, activate(entity, goober, now)}
    end
  end

  def finish(
        %GameObject{internal: %{goober: %Goober{} = goober, object_action: %{revision: revision, active?: true}}} =
          entity,
        revision
      ) do
    entity = GameObjectActions.reset(entity)

    if goober.consumable? or is_integer(entity.game_object.created_by) do
      entity
      |> put_goober(%{goober | depleted?: true})
      |> Effects.enqueue(%Effects.RemoveSelf{respawn_delay_ms: respawn_delay(entity)})
    else
      entity
    end
  end

  def finish(%GameObject{} = entity, _revision), do: entity

  defp activate(entity, goober, now) do
    entity = GameObjectActions.operate(entity, :open, 0)

    entity =
      if goober.custom_animation? do
        %{entity | game_object: %{entity.game_object | state: entity.internal.object_action.default_state}}
        |> Effects.enqueue(Effects.game_object_custom_animation(0))
      else
        entity
      end

    delay = max(goober.auto_close_ms, 1_000)

    entity
    |> put_goober(%{goober | ready_at: now + goober.auto_close_ms})
    |> Effects.enqueue(%Effects.FinishGameObjectUse{revision: entity.internal.object_action.revision, delay_ms: delay})
  end

  defp put_goober(entity, goober), do: %{entity | internal: %{entity.internal | goober: goober}}

  defp respawn_delay(%GameObject{internal: %{spawn: %{respawn_delay_ms: delay}}}), do: delay
  defp respawn_delay(%GameObject{}), do: nil
end
