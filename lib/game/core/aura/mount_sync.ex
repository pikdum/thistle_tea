defmodule ThistleTea.Game.Core.Aura.MountSync do
  @moduledoc """
  Projects mount auras into the unit display without overwriting mounts
  owned by taxi flights or creature scripts during unrelated aura changes.
  """
  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Combat.ExtraAttacks
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Spell

  def interrupt_holders(previous, desired) do
    desired = dismount_on_transform(previous, desired)

    case {mounted?(previous), mounted?(desired)} do
      {false, true} -> Enum.reject(desired, &Holder.interruptible?(&1, 0x00020000))
      {true, false} -> Enum.reject(desired, &Holder.interruptible?(&1, 0x00000040))
      _ -> desired
    end
  end

  def sync(%{internal: %{taxi_flight: flight}} = entity, _previous, _holders) when not is_nil(flight), do: entity

  def sync(%{unit: %Unit{} = unit} = entity, previous, holders) do
    entity = if not mounted?(previous) and mounted?(holders), do: ExtraAttacks.clear(entity), else: entity

    if mounted?(previous) or mounted?(holders) do
      display = holders |> Enum.flat_map(& &1.auras) |> Enum.find_value(0, &mount_display/1)

      %{entity | unit: %{unit | mount_display_id: display}}
    else
      entity
    end
  end

  defp mount_display(%Aura{type: :mounted, misc_value: display}) when is_integer(display) and display > 0, do: display
  defp mount_display(_aura), do: nil

  defp mounted?(holders), do: Enum.any?(holders, &Holder.has_aura_type?(&1, :mounted))

  defp dismount_on_transform(previous, desired) do
    applications = previous |> Enum.filter(&dismounts?/1) |> MapSet.new(&application/1)

    if Enum.any?(desired, &(dismounts?(&1) and not MapSet.member?(applications, application(&1)))),
      do: Enum.reject(desired, &Holder.has_aura_type?(&1, :mounted)),
      else: desired
  end

  defp application(%Holder{} = holder), do: {Holder.key(holder), holder.applied_at}

  defp dismounts?(%Holder{spell: %Spell{id: 4060}, auras: auras}) do
    Enum.any?(auras, &match?(%Aura{index: 0, type: :transform}, &1))
  end

  defp dismounts?(_holder), do: false
end
