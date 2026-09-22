defmodule ThistleTea.Game.Entity.Logic.Aura.MountSync do
  @moduledoc """
  Projects mount auras into the unit display without overwriting mounts
  owned by taxi flights or creature scripts during unrelated aura changes.
  """
  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.ExtraAttacks

  def interrupt_holders(previous, desired) do
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
end
