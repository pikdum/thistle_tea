defmodule ThistleTea.Game.Spell.Stealth do
  @moduledoc """
  Stealth requirements and preservation for a single cast. Improved Sap uses
  one percentile roll supplied by the caster's owner; its result survives
  preparation and completion without recreating a removed stealth aura.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Spell

  @stealth_icons [250, 103, 252]
  @sap_icon 249
  @improved_sap [{14_095, 90}, {14_094, 60}, {14_076, 30}]

  def validate(caster, %Spell{} = spell, opts \\ []) do
    if Spell.attribute?(spell, :only_stealthed) and not Keyword.get(opts, :triggered?, false) and
         not Aura.has_aura?(caster, :mod_stealth),
       do: {:error, :only_stealthed},
       else: :ok
  end

  def exempt?(%Spell{spell_icon: icon} = spell),
    do: icon in @stealth_icons or Spell.attribute?(spell, :allow_while_stealthed)

  def preservation_chance(caster, %Spell{} = spell) do
    if exempt?(spell), do: 100, else: improved_sap_chance(caster, spell)
  end

  def preserve?(caster, spell, roll) do
    chance = preservation_chance(caster, spell)
    chance == 100 or (is_integer(roll) and roll in 1..100 and roll <= chance)
  end

  defp improved_sap_chance(%Character{} = caster, %Spell{spell_icon: @sap_icon}) do
    Enum.find_value(@improved_sap, 0, fn {id, chance} -> if Aura.has_spell?(caster, id), do: chance end)
  end

  defp improved_sap_chance(_caster, _spell), do: 0
end
