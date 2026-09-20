defmodule ThistleTea.Game.Entity.Logic.PetUntraining do
  @moduledoc """
  Hunter pet untraining: escalating daily prices, ability removal, and point refunds.
  Family passives and canonical progression are supplied by the owning boundary.
  """

  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.PetLoyalty
  alias ThistleTea.Game.Entity.Logic.PetTraining

  @day_ms 86_400_000

  def cost(%Pet{last_untrain_cost: previous, last_untrain_at: last}, now) when is_integer(now) do
    cond do
      is_nil(last) or now - last >= @day_ms or previous < 1_000 -> 1_000
      previous < 5_000 -> 5_000
      previous < 10_000 -> 10_000
      true -> min(previous + 10_000, 100_000)
    end
  end

  def quote(
        %Mob{
          internal: %{
            pet: %Pet{kind: :hunter, owner_guid: owner, broken?: false, possessed?: false} = control,
            spellbook: spells
          }
        },
        owner,
        now
      )
      when is_map(spells) and map_size(spells) > 1 do
    {:ok, cost(control, now)}
  end

  def quote(_pet, _owner, _now), do: {:error, :no_pet}

  def reset(%Mob{} = pet, owner, money, maximum_cost, family_spells, now) do
    with {:ok, cost} <- quote(pet, owner, now),
         true <- cost <= maximum_cost,
         true <- money >= cost do
      {:ok, clear(pet, family_spells, cost, now), cost}
    else
      false -> {:error, :not_enough_money}
      error -> error
    end
  end

  defp clear(%Mob{} = pet, family_spells, cost, now) do
    removed_ids = Map.keys(pet.internal.spellbook) -- Map.keys(family_spells)
    pet = Casting.cancel(pet)
    {pet, effects} = Aura.remove_spells(pet, removed_ids, now)

    action_bar =
      Map.new(pet.internal.pet.action_bar, fn
        {slot, {_id, type}} when type in [0x01, 0x81, 0xC1] -> {slot, {0, 0x81}}
        entry -> entry
      end)

    control = %{
      pet.internal.pet
      | action_bar: action_bar,
        autocast: MapSet.new(),
        family_spells: MapSet.new(Map.keys(family_spells)),
        last_untrain_cost: cost,
        last_untrain_at: now
    }

    creature = %{pet.internal.creature | spells: PetTraining.action_spells(family_spells)}
    pet = %{pet | internal: %{pet.internal | spellbook: family_spells, pet: control, creature: creature}}

    pet
    |> Effects.enqueue(effects)
    |> PetLoyalty.refund_training_points()
    |> PetTraining.restore_passives(now)
    |> Core.mark_broadcast_update()
  end
end
