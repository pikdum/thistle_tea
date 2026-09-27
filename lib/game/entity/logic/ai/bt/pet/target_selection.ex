defmodule ThistleTea.Game.Entity.Logic.AI.BT.Pet.TargetSelection do
  @moduledoc "Selects a pet's next combat victim from immutable attacker and owner observations."

  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Pet.Targeting
  alias ThistleTea.Game.Guid

  def next(
        %Mob{internal: %{pet: %Pet{owner_guid: owner}, world: world}} = pet,
        %Context{perception: perception} = context,
        excluded_guid \\ nil
      ) do
    with {^world, _, _, _} <- Perception.position(perception, owner),
         metadata when is_map(metadata) <- Perception.metadata(perception, owner),
         false <- Map.get(metadata, :evading?, false) do
      pet
      |> candidates(owner, metadata, perception)
      |> Enum.uniq()
      |> Enum.reject(&(&1 == excluded_guid))
      |> Enum.find(&Targeting.retaliation?(pet, &1, context))
    else
      _ -> nil
    end
  end

  defp candidates(pet, owner, metadata, perception) do
    own =
      if Guid.entity_type(owner) == :player,
        do: attackers(perception, pet.object.guid),
        else: threat_targets(pet)

    if Map.get(metadata, :in_combat, false) do
      own ++ [Map.get(metadata, :combat_victim_guid)] ++ attackers(perception, owner)
    else
      own
    end
    |> Enum.filter(&(is_integer(&1) and &1 > 0))
  end

  defp threat_targets(%Mob{internal: %{threat: threat}}) do
    threat
    |> Kernel.||(%{})
    |> Enum.sort_by(fn {guid, amount} -> {-amount, guid} end)
    |> Enum.map(&elem(&1, 0))
  end

  defp attackers(%Perception{entities: observations}, victim) do
    observations
    |> Enum.filter(fn {_guid, observation} -> attacking?(observation.metadata, victim) end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.sort()
  end

  defp attacking?(%{in_combat: true, combat_victim_guid: victim}, victim), do: true
  defp attacking?(_metadata, _victim), do: false
end
