defmodule ThistleTea.Game.Core.Spell.Immunity do
  @moduledoc "Immunity grants that purge existing effects, derived from a spell or an active aura holder."

  import Bitwise, only: [band: 2, bor: 2, <<<: 2]

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Effect

  defstruct schools: 0, mechanics: MapSet.new(), dispels: MapSet.new(), states: MapSet.new()

  def targeted_school_protection?(%Spell{} = spell) do
    first = Enum.find(spell.effects, &(&1.index == 0))

    not Spell.attribute?(spell, :ignore_caster_and_target_restrictions) and
      match?(
        %Effect{implicit_target_a: target} when target in [:target_ally, :party_member, :chain_heal, :raid_and_class],
        first
      ) and
      (spell.triggers_school_immunity? or Enum.any?(spell.effects, &(&1.aura == :school_immunity)))
  end

  def purging(%Spell{} = spell) do
    grants = Enum.map(Spell.aura_effects(spell), fn %Effect{} = effect -> {effect.aura, effect.misc_value} end)
    build(spell, grants)
  end

  def purging(%Holder{spell: spell, auras: auras}) do
    grants = Enum.map(auras, fn %Aura{} = aura -> {aura.type, aura.misc_value} end)
    build(spell, grants)
  end

  def granted_mechanics(:mechanic_immunity, mechanic) when is_integer(mechanic) and mechanic > 0, do: [mechanic]

  def granted_mechanics(:mechanic_immunity_mask, mask) when is_integer(mask),
    do: for(mechanic <- 1..32, band(mask, 1 <<< (mechanic - 1)) != 0, do: mechanic)

  def granted_mechanics(_type, _misc_value), do: []

  def empty?(%__MODULE__{} = immunity), do: immunity == %__MODULE__{}

  def school?(%__MODULE__{schools: schools}, %Spell{} = spell), do: band(schools, Spell.school_mask(spell)) != 0

  def mechanic?(%__MODULE__{mechanics: mechanics}, mechanic), do: MapSet.member?(mechanics, mechanic)
  def dispel?(%__MODULE__{dispels: dispels}, %Spell{dispel_type: dispel}), do: MapSet.member?(dispels, dispel)
  def state?(%__MODULE__{states: states}, type), do: MapSet.member?(states, type)

  defp build(spell, grants) do
    if Spell.attribute?(spell, :immunity_purges_effect),
      do: Enum.reduce(grants, %__MODULE__{}, &add/2),
      else: %__MODULE__{}
  end

  defp add({:school_immunity, mask}, immunity) when is_integer(mask) and mask > 0,
    do: %{immunity | schools: bor(immunity.schools, mask)}

  defp add({type, misc_value}, immunity) when type in [:mechanic_immunity, :mechanic_immunity_mask],
    do: %{immunity | mechanics: MapSet.union(immunity.mechanics, MapSet.new(granted_mechanics(type, misc_value)))}

  defp add({:dispel_immunity, dispel}, immunity) when is_integer(dispel) and dispel > 0,
    do: %{immunity | dispels: MapSet.put(immunity.dispels, dispel)}

  defp add({:state_immunity, type}, immunity) when is_atom(type) and not is_nil(type),
    do: %{immunity | states: MapSet.put(immunity.states, type)}

  defp add(_grant, immunity), do: immunity
end
