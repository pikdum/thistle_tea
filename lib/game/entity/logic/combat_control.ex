defmodule ThistleTea.Game.Entity.Logic.CombatControl do
  @moduledoc """
  Pacification and silence derived from active auras. Combined controls share
  the same attack restrictions, spell prevention rules, and client flags as
  their independent counterparts.
  """
  import Bitwise, only: [&&&: 2, |||: 2, bnot: 1]

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.ControlMovement
  alias ThistleTea.Game.Spell

  @pacified 0x00020000
  @silenced 0x00002000

  def pacified?(entity), do: has_control?(entity, [:mod_pacify, :mod_pacify_silence])
  def silenced?(entity), do: has_control?(entity, [:mod_silence, :mod_pacify_silence])

  def auto_attack_blocked?(entity) do
    pacified?(entity) or ControlMovement.active?(entity) or has_control?(entity, [:mod_stun, :feign_death])
  end

  def prevention(entity, %Spell{prevention_type: 1}) do
    if silenced?(entity), do: {:error, :silenced}, else: :ok
  end

  def prevention(entity, %Spell{prevention_type: 2}) do
    if pacified?(entity), do: {:error, :pacified}, else: :ok
  end

  def prevention(_entity, %Spell{}), do: :ok

  def sync(%Unit{auras: holders} = unit) when is_list(holders) do
    flags = (unit.flags || 0) &&& bnot(@pacified ||| @silenced)
    flags = if pacified?(%{unit: unit}), do: flags ||| @pacified, else: flags
    flags = if silenced?(%{unit: unit}), do: flags ||| @silenced, else: flags
    %{unit | flags: flags}
  end

  def sync(unit), do: unit

  defp has_control?(%{unit: %Unit{auras: holders}}, types) when is_list(holders),
    do: Enum.any?(holders, &Holder.has_any_type?(&1, types))

  defp has_control?(_entity, _types), do: false
end
