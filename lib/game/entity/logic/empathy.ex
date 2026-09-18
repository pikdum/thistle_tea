defmodule ThistleTea.Game.Entity.Logic.Empathy do
  @moduledoc """
  Derives Beast Lore's special-information flag and caster-specific access
  from active empathy holders, without retaining access after aura removal.
  """
  import Bitwise, only: [&&&: 2, |||: 2, bnot: 1]

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Unit

  @special_info 0x0010

  def sync(%Unit{} = unit) do
    set_flag(unit, Enum.any?(unit.auras || [], &Holder.has_aura_type?(&1, :empathy)))
  end

  def visible_to?(%Unit{auras: holders}, viewer) when is_list(holders) and is_integer(viewer) and viewer > 0 do
    Enum.any?(holders, fn %Holder{caster_guid: caster} = holder ->
      caster == viewer and Holder.has_aura_type?(holder, :empathy)
    end)
  end

  def visible_to?(_unit, _viewer), do: false

  def project(%Unit{dynamic_flags: nil} = unit, _viewer), do: unit
  def project(%Unit{} = unit, viewer), do: set_flag(unit, visible_to?(unit, viewer))

  defp set_flag(%Unit{dynamic_flags: flags} = unit, active?) do
    flags = flags || 0
    flags = if active?, do: flags ||| @special_info, else: flags &&& bnot(@special_info)
    %{unit | dynamic_flags: flags}
  end
end
