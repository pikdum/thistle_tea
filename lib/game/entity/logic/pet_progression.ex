defmodule ThistleTea.Game.Entity.Logic.PetProgression do
  @moduledoc """
  Hunter pet experience and level transitions over a supplied growth catalogue.
  Level growth recomputes canonical stats, restores health and focus, and
  publishes the retained progress through the owning entity's effect stream.
  """

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.PetLevel
  alias ThistleTea.Game.Entity.Data.PetProgress
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Experience
  alias ThistleTea.Game.Entity.Logic.PetLoyalty
  alias ThistleTea.Game.Entity.Logic.Stats

  @max_level 60

  def snapshot(%Mob{internal: %Internal{pet: %Pet{kind: :hunter} = pet, spellbook: spellbook}, unit: %Unit{} = unit}) do
    %PetProgress{
      level: unit.level,
      xp: unit.pet_experience || 0,
      spells: Map.keys(spellbook || %{}) |> Enum.sort(),
      loyalty: unit.pet_loyalty,
      loyalty_points: pet.loyalty_points,
      training_points: pet.training_points
    }
  end

  def snapshot(_entity), do: nil

  def initialize(%Mob{internal: %Internal{pet: %Pet{kind: :hunter}}} = pet, %PetProgress{} = progress, levels) do
    pet = apply_level(pet, Map.fetch!(levels, progress.level))
    pet = PetLoyalty.initialize(pet, progress)
    %{pet | unit: %{pet.unit | pet_experience: max(progress.xp, 0)}}
  end

  def initialize(pet, _progress, _levels), do: pet

  def reward(%Mob{} = pet, {:solo, level, opts}), do: Experience.kill_xp(pet.unit.level, level, opts)
  def reward(%Mob{}, {:group, amount}) when is_integer(amount), do: amount
  def reward(_pet, _reward), do: 0

  def gain(
        %Mob{internal: %Internal{pet: %Pet{kind: :hunter, broken?: false}}, unit: %Unit{health: health, level: level}} =
          pet,
        amount,
        owner_level,
        levels
      )
      when is_integer(amount) and amount > 0 and is_number(health) and health > 0 and is_integer(owner_level) and
             level < owner_level and level < @max_level do
    pet
    |> advance((pet.unit.pet_experience || 0) + amount, min(owner_level, @max_level), levels)
    |> PetLoyalty.kill_bonus()
    |> publish()
    |> Core.mark_broadcast_update()
  end

  def gain(pet, _amount, _owner_level, _levels), do: pet

  defp advance(%Mob{unit: %Unit{level: level}} = pet, xp, cap, levels) do
    cost = Map.fetch!(levels, level).next_level_xp

    cond do
      level >= cap ->
        %{pet | unit: %{pet.unit | pet_experience: 0}}

      cost <= 0 ->
        pet

      xp < cost ->
        %{pet | unit: %{pet.unit | pet_experience: xp, pet_next_level_exp: cost}}

      true ->
        pet |> apply_level(Map.fetch!(levels, level + 1)) |> PetLoyalty.level_up() |> advance(xp - cost, cap, levels)
    end
  end

  def publish(%Mob{} = pet) do
    Effects.enqueue(pet, %Effects.PetProgressChanged{
      source_guid: pet.object.guid,
      target_guid: pet.internal.pet.owner_guid,
      progress: snapshot(pet)
    })
  end

  defp apply_level(%Mob{unit: %Unit{} = unit} = pet, %PetLevel{} = stats) do
    speed = (unit.base_attack_time || 2_000) / 1_000
    attack_power_damage = max(stats.strength * 2 - 20, 0) / 14 * speed

    unit =
      %{
        unit
        | level: stats.level,
          base_strength: stats.strength,
          base_agility: stats.agility,
          base_stamina: stats.stamina,
          base_intellect: stats.intellect,
          base_spirit: stats.spirit,
          base_health: stats.health - Stats.stamina_health_bonus(stats.stamina),
          base_normal_resistance: stats.armor,
          base_min_damage: stats.level * 1.15 * 1.05 * speed / 2 - attack_power_damage,
          base_max_damage: stats.level * 1.45 * 1.05 * speed / 2 - attack_power_damage,
          pet_experience: 0,
          pet_next_level_exp: stats.next_level_xp
      }
      |> Stats.recompute()

    %{pet | unit: %{unit | health: unit.max_health, power3: unit.max_power3}}
  end
end
