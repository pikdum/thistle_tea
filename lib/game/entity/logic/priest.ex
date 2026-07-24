defmodule ThistleTea.Game.Entity.Logic.Priest do
  @moduledoc """
  Priest-specific spell pairs mirrored from the VMangos priest spell
  scripts: Power Word: Shield's Weakened Soul, Holy Nova's paired heal,
  and Touch of Weakness' damage proc, keyed per rank.
  """
  alias ThistleTea.Game.Spell

  @weakened_soul 6788
  @vampiric_embrace 15_286
  @vampiric_embrace_heal 15_290

  @holy_nova_heals %{
    15_237 => 23_455,
    15_430 => 23_458,
    15_431 => 23_459,
    27_799 => 27_803,
    27_800 => 27_804,
    27_801 => 27_805
  }

  @touch_of_weakness_damage %{
    2652 => 2943,
    19_261 => 19_249,
    19_262 => 19_251,
    19_264 => 19_252,
    19_265 => 19_253,
    19_266 => 19_254
  }

  def weakened_soul_id, do: @weakened_soul

  def shield_trigger_id(%Spell{} = spell) do
    if Spell.vmangos_script?(spell, "spell_priest_power_word_shield"), do: @weakened_soul
  end

  def shield_trigger_id(_spell), do: nil

  def holy_nova_heal_id(%Spell{id: id} = spell) do
    if Spell.vmangos_script?(spell, "spell_priest_holy_nova"), do: Map.get(@holy_nova_heals, id)
  end

  def holy_nova_heal_id(_spell), do: nil

  def vampiric_embrace?(%Spell{id: @vampiric_embrace}), do: true
  def vampiric_embrace?(_spell), do: false

  def vampiric_embrace_heal_id, do: @vampiric_embrace_heal

  def touch_of_weakness?(%Spell{} = spell), do: Spell.vmangos_script?(spell, "spell_priest_touch_of_weakness")
  def touch_of_weakness?(_spell), do: false

  def touch_of_weakness_damage_id(triggering_spell_id), do: Map.get(@touch_of_weakness_damage, triggering_spell_id)
end
