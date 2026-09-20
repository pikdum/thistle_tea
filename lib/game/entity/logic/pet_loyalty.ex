defmodule ThistleTea.Game.Entity.Logic.PetLoyalty do
  @moduledoc """
  Hunter pet loyalty transitions, training-point earnings, and neglect.
  The owner retains progress while suspended; only an active, living pet
  earns timed loyalty. A broken bond emits one request to remove the pet.
  """

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.PetProgress
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.PetProgression

  @tick_ms 12_000
  @thresholds {5_500, 11_500, 17_000, 23_500, 31_000, 39_500}
  @starting_points {2_000, 4_500, 7_000, 10_000, 13_500, 17_500}

  def initialize(%Mob{internal: %Internal{pet: %Pet{kind: :hunter} = pet}} = entity, %PetProgress{} = progress) do
    pet = %{pet | loyalty_points: progress.loyalty_points, training_points: progress.training_points}

    %{entity | internal: %{entity.internal | pet: pet}, unit: %{entity.unit | pet_loyalty: progress.loyalty}}
    |> project_training_points()
  end

  def next_tick_at(%Mob{
        internal: %Internal{pet: %Pet{kind: :hunter, broken?: false} = pet},
        unit: %Unit{health: health}
      })
      when is_number(health) and health > 0, do: pet.next_loyalty_at

  def next_tick_at(_entity), do: nil

  def tick(
        %Mob{internal: %Internal{pet: %Pet{kind: :hunter, broken?: false} = pet}, unit: %Unit{health: health}} = entity,
        now
      )
      when is_number(health) and health > 0 and is_integer(now) do
    cond do
      is_nil(pet.next_loyalty_at) -> schedule(entity, now + @tick_ms)
      now < pet.next_loyalty_at -> entity
      true -> entity |> change(tick_amount(entity.unit.power5)) |> publish_change(entity) |> schedule(now + @tick_ms)
    end
  end

  def tick(entity, _now), do: entity

  def pause(%Mob{internal: %Internal{pet: %Pet{kind: :hunter}}} = entity), do: schedule(entity, nil)
  def pause(entity), do: entity

  def change(
        %Mob{internal: %Internal{pet: %Pet{kind: :hunter, broken?: false} = pet}, unit: %Unit{} = unit} = entity,
        amount
      )
      when is_integer(amount) do
    points = pet.loyalty_points + amount
    rank = unit.pet_loyalty

    cond do
      rank == 6 and points > elem(@thresholds, 5) -> entity
      points < 0 and rank == 1 -> break_bond(entity)
      points < 0 -> change_rank(entity, rank - 1, -unit.level)
      points > elem(@thresholds, rank - 1) -> change_rank(entity, rank + 1, unit.level)
      true -> %{entity | internal: %{entity.internal | pet: %{pet | loyalty_points: points}}}
    end
  end

  def change(entity, _amount), do: entity

  def kill_bonus(%Mob{unit: %Unit{level: level, pet_loyalty: rank}} = entity) do
    change(entity, div(100 - level, 10) + 6 - rank)
  end

  def level_up(%Mob{unit: %Unit{pet_loyalty: rank}} = entity), do: add_training_points(entity, rank - 1)

  defp tick_amount(happiness) when happiness >= 666_000, do: 20
  defp tick_amount(happiness) when happiness >= 333_000, do: 10
  defp tick_amount(_happiness), do: -20

  defp change_rank(%Mob{} = entity, rank, training) do
    pet = %{entity.internal.pet | loyalty_points: elem(@starting_points, rank - 1)}

    %{entity | unit: %{entity.unit | pet_loyalty: rank}, internal: %{entity.internal | pet: pet}}
    |> add_training_points(training)
    |> Core.mark_broadcast_update()
  end

  defp add_training_points(%Mob{internal: %Internal{pet: %Pet{} = pet}} = entity, amount) do
    %{entity | internal: %{entity.internal | pet: %{pet | training_points: pet.training_points + amount}}}
    |> project_training_points()
  end

  defp project_training_points(%Mob{internal: %Internal{pet: %Pet{training_points: points}}} = entity) do
    displayed = if points < 0, do: -points, else: -(points + 1)
    %{entity | unit: %{entity.unit | training_points: displayed}}
  end

  defp break_bond(%Mob{} = entity) do
    pet = %{entity.internal.pet | loyalty_points: 0, broken?: true, next_loyalty_at: nil}

    %{entity | internal: %{entity.internal | pet: pet}}
    |> Effects.enqueue(%Effects.PetBroke{source_guid: entity.object.guid, target_guid: pet.owner_guid})
  end

  defp publish_change(entity, entity), do: entity
  defp publish_change(%Mob{internal: %{pet: %Pet{broken?: true}}} = entity, _previous), do: entity
  defp publish_change(entity, _previous), do: PetProgression.publish(entity)

  defp schedule(%Mob{internal: %Internal{pet: %Pet{broken?: true}}} = entity, _at), do: entity

  defp schedule(%Mob{internal: %Internal{pet: %Pet{} = pet} = internal} = entity, at) do
    %{entity | internal: %{internal | pet: %{pet | next_loyalty_at: at}}}
  end
end
