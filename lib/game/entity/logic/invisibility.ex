defmodule ThistleTea.Game.Entity.Logic.Invisibility do
  @moduledoc """
  Typed invisibility and detection levels derived from active auras. A shared
  invisibility type or sufficient detection of any type reveals the target,
  following vanilla detection rules. World bosses detect every type.
  """
  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic

  def metadata(entity) do
    %{
      invisibility: levels(entity, :mod_invisibility),
      invisibility_detection: detection_levels(entity),
      detects_all_invisibility?: world_boss?(entity)
    }
  end

  def detectable?(detector, target) when is_map(detector) and is_map(target) do
    invisible = Map.get(target, :invisibility, %{})
    shared = Map.get(detector, :invisibility, %{})
    detection = Map.get(detector, :invisibility_detection, %{})

    invisible == %{} or Map.get(detector, :detects_all_invisibility?, false) or
      Enum.any?(invisible, fn {type, level} ->
        Map.has_key?(shared, type) or Map.get(detection, type, 0) >= level
      end)
  end

  def detectable?(_detector, _target), do: false

  defp levels(entity, type) do
    entity
    |> AuraLogic.auras_of_type(type)
    |> Enum.reduce(%{}, fn
      %Aura{misc_value: type, amount: amount}, levels when type in 0..31 and is_integer(amount) ->
        Map.update(levels, type, max(amount, 0), &max(&1, amount))

      _aura, levels ->
        levels
    end)
  end

  defp detection_levels(%Character{player: %{drunk_value: drunk}} = entity) do
    entity |> levels(:mod_invisibility_detect) |> Map.put(6, drunk || 0)
  end

  defp detection_levels(entity), do: levels(entity, :mod_invisibility_detect)

  defp world_boss?(%Mob{internal: %{creature: %{rank: 3}}}), do: true
  defp world_boss?(_entity), do: false
end
