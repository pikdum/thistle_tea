defmodule ThistleTea.Game.Entity.Logic.Aura.Priority do
  @moduledoc "Vanilla aura replacement priorities from VMangos SpellAuraHolder, including rank and family exceptions."

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Spell

  @rank_groups [
    {0, ~w(
      1604 2094 3409 11201 3600 4066 4067 4069 4507 5246
      5530 6358 6788 9672 339 2908 8056 8122 605 6770
      18202 18075 17511 17504 17484 17483 17407 17196 16406 14914
      21162 13752 12328 13526 13318 11366 133 12721 24388 21159
      21151 12421 12562 118 13237 13327 13747 13808 14251 3355
      14308 14309 15235 15487 8034 16454 17153 5484 18093 18118
      18223 710 18798 19229 19410 19755 19784 19872 19975 19974
      19973 19972 19971 19970 20066 20586 24375 24394
    )},
    {1, ~w(
      1833 5917 7922 9658 10578 2096 453 1714 11103 11113
      2974 3043 16413 16415 17330 17506 17639 18289 18425 18469
      18498 19821 20184 20511 22639 23023 28272
    )},
    {2, ~w(
      12579 67 26017 26018 23605 702 11374 8921 18265 980
      13797 1978 21992 2818 348 23577 17315 16928 17877 23415
      9035 2944 24640 12766 2943 19249 19251 19252 19253 19254
      8050 172 16528 15258 13003 589 12654
    )},
    {3, ~w(
      355 603 676 1161 1543 2855 4068 5116 5209 5782
      770 16857 120 10 2120 122 853 5760 8692 11398
      1120 5740 689 5138 704 1490 12323 11071 12543 12798
      12809 13218 13810 3034 1510 13812 1130 15286 15268 15407
      16922 17364 16914 17794 6789 17862 18656 2637 19185 10797
      19503 19675 19769 20006 21183 20188 20300 20301 20302 20303
      20185 20344 20345 20346 20186 20354 20355 20549 20253 20614
      20615 20116 26573 21152 22959 23454 23694 24423 5570 116
      25999
    )},
    {4, ~w(
      6136 6795 17331 27648 24323 24322 28732 25181 25177 25178
      25180 25183 7321 16597 20005
    )}
  ]

  @rank_priorities Map.new(for {priority, ids} <- @rank_groups, id <- ids, do: {String.to_integer(id), priority})

  @family_priorities [
    {8, 0x8, 1},
    {8, 0x100100, 2},
    {4, 0x20, 2},
    {7, 0x801000, 2},
    {4, 0xA004082, 3},
    {8, 0x2280000, 3},
    {7, 0x2000, 3},
    {4, 0x20000, 4},
    {7, 0x8, 4}
  ]

  @control_auras [:mod_taunt, :mod_threat, :mod_charm, :mod_fear, :mod_confuse, :mod_possess, :mod_stun]
  @group_auras [
    :mod_resistance,
    :mod_language,
    :mod_stalked,
    :mod_disarm,
    :mod_damage_percent_taken,
    :prevent_fleeing,
    :mod_attacker_spell_crit_chance,
    :mod_melee_haste,
    :mod_attack_speed,
    :mod_attack_power,
    :mod_damage_done,
    :mod_damage_taken,
    :mod_healing_pct
  ]

  def value(%Holder{negative?: false} = holder, target_guid) do
    cond do
      holder.expires_at in [nil, -1] -> 3
      holder.caster_guid != target_guid -> 2
      is_integer(holder.cast_item_guid) and holder.cast_item_guid > 0 -> 1
      true -> 0
    end
  end

  def value(%Holder{spell: %Spell{} = spell} = holder, _target_guid) do
    case family_priority(spell) || Map.get(@rank_priorities, spell.first_in_chain || spell.id) do
      nil -> effect_priority(holder)
      priority -> priority
    end
  end

  defp family_priority(spell) do
    Enum.find_value(@family_priorities, fn {family, mask, priority} ->
      if Spell.family_flag?(spell, family, mask), do: priority
    end)
  end

  defp effect_priority(%Holder{spell: spell} = holder) do
    cond do
      Holder.charm?(holder) ->
        adjust_priority(4, holder)

      Holder.has_aura_type?(holder, :ranged_attack_power_attacker_bonus) ->
        3

      Holder.has_aura_type?(holder, :dummy) and {spell.spell_visual, spell.spell_icon} == {3582, 150} ->
        3

      true ->
        priority = holder.auras |> Enum.map(&aura_priority(&1.type)) |> Enum.max(fn -> 0 end)
        adjust_priority(priority, holder)
    end
  end

  defp adjust_priority(priority, %Holder{triggered?: true}) when priority > 2, do: 2
  defp adjust_priority(_priority, %Holder{triggered?: true}), do: 0

  defp adjust_priority(priority, %Holder{spell: spell}) do
    if Spell.attribute?(spell, :channeled), do: max(priority, 1), else: priority
  end

  defp aura_priority(type) when type in @control_auras, do: 4
  defp aura_priority(type) when type in @group_auras, do: 3
  defp aura_priority(type) when type in [:periodic_damage, :periodic_damage_percent, :periodic_leech], do: 1
  defp aura_priority(_type), do: 0
end
