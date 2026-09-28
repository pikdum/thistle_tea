defmodule ThistleTea.Game.Spell.Immunity do
  @moduledoc "Immunity grants that purge existing effects, derived from a spell or an active aura holder."

  import Bitwise, only: [band: 2, bor: 2]

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  defstruct schools: 0, mechanics: MapSet.new(), dispels: MapSet.new(), states: MapSet.new()

  def purging(%Spell{} = spell) do
    grants = Enum.map(Spell.aura_effects(spell), fn %Effect{} = effect -> {effect.aura, effect.misc_value} end)
    build(spell, grants)
  end

  def purging(%Holder{spell: spell, auras: auras}) do
    grants = Enum.map(auras, fn %Aura{} = aura -> {aura.type, aura.misc_value} end)
    build(spell, grants)
  end

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

  defp add({:mechanic_immunity, mechanic}, immunity) when is_integer(mechanic) and mechanic > 0,
    do: %{immunity | mechanics: MapSet.put(immunity.mechanics, mechanic)}

  defp add({:dispel_immunity, dispel}, immunity) when is_integer(dispel) and dispel > 0,
    do: %{immunity | dispels: MapSet.put(immunity.dispels, dispel)}

  defp add({:state_immunity, type}, immunity) when is_atom(type) and not is_nil(type),
    do: %{immunity | states: MapSet.put(immunity.states, type)}

  defp add(_grant, immunity), do: immunity
end
