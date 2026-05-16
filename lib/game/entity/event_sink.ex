defmodule ThistleTea.Game.Entity.EventSink do
  alias ThistleTea.Character
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World

  def emit(entity, events) when is_list(events) do
    Enum.each(events, &emit(entity, &1))
    entity
  end

  def emit(entity, %Event{type: :spell_damage} = event) do
    %Message.SmsgSpellNonMeleeDamageLog{
      attacker: event.source_guid || 0,
      target: event.target_guid,
      spell_id: event.spell_id,
      damage: event.damage,
      school: school_index(event.school),
      periodic?: event.periodic?
    }
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(entity, %Event{type: :aura_duration} = event) do
    Network.send_packet(%Message.SmsgUpdateAuraDuration{
      aura_slot: event.aura_slot,
      duration_ms: event.duration_ms
    })

    entity
  end

  def emit(%Mob{} = entity, %Event{type: :movement_stopped}) do
    World.update_position(entity)

    Message.SmsgMonsterMove.build_stop(entity)
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(%Character{} = entity, %Event{type: :movement_stopped}) do
    World.update_position(entity)
    entity
  end

  def emit(entity, _event), do: entity

  defp school_index(:physical), do: 0
  defp school_index(:holy), do: 1
  defp school_index(:fire), do: 2
  defp school_index(:nature), do: 3
  defp school_index(:frost), do: 4
  defp school_index(:shadow), do: 5
  defp school_index(:arcane), do: 6
  defp school_index(other) when is_integer(other), do: other
  defp school_index(_), do: 0
end
