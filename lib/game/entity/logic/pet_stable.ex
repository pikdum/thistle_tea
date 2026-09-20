defmodule ThistleTea.Game.Entity.Logic.PetStable do
  @moduledoc """
  Pure stable purchases and atomic transfers between the current pet and two stable slots.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion, as: CompanionData
  alias ThistleTea.Game.Entity.Data.PetStable
  alias ThistleTea.Game.Entity.Logic.Companion

  def buy(%Character{internal: %{pet_stable: %PetStable{slots: slots}}} = character, cost)
      when slots < 2 and is_integer(cost) and cost >= 0 do
    if character.player.coinage >= cost do
      stable = %{character.internal.pet_stable | slots: slots + 1}
      player = %{character.player | coinage: character.player.coinage - cost}
      {:ok, %{character | player: player, internal: %{character.internal | pet_stable: stable}}}
    else
      {:error, :money}
    end
  end

  def buy(%Character{}, _cost), do: {:error, :stable}

  def transfer(%Character{} = character, :store) do
    stable = character.internal.pet_stable

    with %CompanionData{kind: :hunter_pet, pet_number: number} when is_integer(number) <-
           Companion.relationship(character),
         slot when is_integer(slot) <- Enum.find([1, 2], &(&1 <= stable.slots and not Map.has_key?(stable.pets, &1))) do
      companion = character |> Companion.suspend() |> Companion.relationship()
      stable = %{stable | pets: Map.put(stable.pets, slot, companion)}
      {:ok, character |> put_stable(stable) |> Companion.clear()}
    else
      _ -> {:error, :stable}
    end
  end

  def transfer(%Character{} = character, {operation, number}) when operation in [:retrieve, :swap] do
    stable = character.internal.pet_stable
    current = Companion.relationship(character)

    with true <- exchange_allowed?(current, operation),
         {slot, companion} <- Enum.find(stable.pets, fn {_slot, pet} -> pet.pet_number == number end) do
      pets =
        case current do
          %CompanionData{kind: :hunter_pet} ->
            suspended = character |> Companion.suspend() |> Companion.relationship()
            Map.put(stable.pets, slot, suspended)

          %CompanionData{status: :none} ->
            Map.delete(stable.pets, slot)
        end

      {:ok, character |> put_stable(%{stable | pets: pets}) |> Companion.restore(companion)}
    else
      _ -> {:error, :stable}
    end
  end

  def entries(%Character{} = character) do
    current =
      case Companion.relationship(character) do
        %CompanionData{kind: :hunter_pet, pet_number: number} = pet when is_integer(number) -> [{1, pet}]
        _ -> []
      end

    current ++ Enum.map(Enum.sort(character.internal.pet_stable.pets), fn {slot, pet} -> {slot + 1, pet} end)
  end

  defp exchange_allowed?(%CompanionData{status: :none}, :retrieve), do: true
  defp exchange_allowed?(%CompanionData{kind: :hunter_pet, status: {:suspended, _, _}}, _operation), do: true
  defp exchange_allowed?(%CompanionData{kind: :hunter_pet}, :swap), do: true
  defp exchange_allowed?(_companion, _operation), do: false

  defp put_stable(%Character{} = character, %PetStable{} = stable) do
    %{character | internal: %{character.internal | pet_stable: stable}}
  end
end
