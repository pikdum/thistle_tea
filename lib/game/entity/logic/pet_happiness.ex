defmodule ThistleTea.Game.Entity.Logic.PetHappiness do
  @moduledoc """
  Hunter pet happiness, its damage multiplier, and timed decay. Happiness is
  stored in the client's resource units; only hunter pets have a happiness
  capacity. Resource changes always recompute damage from canonical inputs.
  """

  import Bitwise, only: [>>>: 2]

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.PetLoyalty
  alias ThistleTea.Game.Entity.Logic.Stats

  @level_size 333_000
  @tick_ms 7_500

  def damage_multiplier(%Unit{power5: happiness, max_power5: capacity})
      when is_integer(happiness) and is_integer(capacity) and capacity > 0 do
    cond do
      happiness < @level_size -> 0.75
      happiness < @level_size * 2 -> 1.0
      true -> 1.25
    end
  end

  def damage_multiplier(%{unit: %Unit{} = unit}), do: damage_multiplier(unit)
  def damage_multiplier(_entity), do: 1.0

  def change(%Mob{internal: %Internal{pet: %Pet{kind: :hunter}}, unit: %Unit{} = unit} = pet, amount)
      when is_integer(unit.power5) and is_integer(unit.max_power5) and is_number(amount) do
    happiness = unit.power5 |> Kernel.+(trunc(amount)) |> max(0) |> min(unit.max_power5)

    if happiness == unit.power5 do
      pet
    else
      %{pet | unit: Stats.recompute(%{unit | power5: happiness})}
      |> Effects.enqueue(%Effects.PetHappinessChanged{
        source_guid: pet.object.guid,
        target_guid: pet.internal.pet.owner_guid,
        happiness: happiness
      })
      |> Core.mark_broadcast_update()
    end
  end

  def change(entity, _amount), do: entity

  def next_tick_at(%Mob{internal: %Internal{pet: %Pet{kind: :hunter} = pet}, unit: %Unit{health: health}})
      when is_number(health) and health > 0, do: pet.next_happiness_at

  def next_tick_at(_entity), do: nil

  def tick(%Mob{internal: %Internal{pet: %Pet{kind: :hunter} = pet}, unit: %Unit{health: health}} = entity, now)
      when is_number(health) and health > 0 and is_integer(now) do
    cond do
      is_nil(pet.next_happiness_at) -> schedule(entity, now + @tick_ms)
      now < pet.next_happiness_at -> entity
      true -> entity |> change(-decay_amount(entity)) |> schedule(now + @tick_ms)
    end
  end

  def tick(entity, _now), do: entity

  def on_death(%Mob{internal: %Internal{pet: %Pet{kind: :hunter}}} = pet, battleground?) do
    pet = if battleground?, do: pet, else: change(pet, -@level_size)

    pet
    |> schedule(nil)
    |> PetLoyalty.pause()
    |> Effects.enqueue(%Effects.PetDied{source_guid: pet.object.guid, target_guid: pet.internal.pet.owner_guid})
  end

  def on_death(entity, _battleground?), do: entity

  defp decay_amount(%Mob{unit: %Unit{pet_loyalty: loyalty}, internal: %Internal{in_combat: combat?}}) do
    loyalty = if loyalty in 1..6, do: loyalty, else: 1
    amount = (140 >>> loyalty) * 125
    if combat?, do: trunc(amount * 1.5), else: amount
  end

  defp schedule(%Mob{internal: %Internal{pet: %Pet{} = pet} = internal} = entity, at) do
    %{entity | internal: %{internal | pet: %{pet | next_happiness_at: at}}}
  end
end
