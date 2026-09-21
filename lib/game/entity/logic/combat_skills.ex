defmodule ThistleTea.Game.Entity.Logic.CombatSkills do
  @moduledoc """
  Weapon-skill snapshots and combat progression. The defender resolves training
  opportunities; the attacker advances the skill used when the attack launched.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.CombatRatings
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Disarm
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell

  @training_outcomes [:normal, :crit, :glancing, :crushing, :miss, :dodge, :parry, :block, :resist]

  def snapshot(%Character{unit: unit, player: player} = character, hand, get_template) when is_struct(player) do
    skill_id = weapon_skill(character, hand, get_template)
    {temporary, permanent} = Map.get(Skills.bonuses(character), skill_id, {0, 0})
    maximum = Skills.max_for_level(unit.level || 1)

    value =
      cond do
        is_nil(skill_id) -> 0
        unit.shapeshift_form in [1, 2, 3, 4, 5, 8] -> maximum
        true -> max(Skills.value(player.skills, skill_id, maximum) + temporary + permanent, 0)
      end

    %{
      caster_attack_skill: value,
      weapon_skill_id: if(trainable_form?(unit.shapeshift_form) and skill_id != Skills.fishing_skill(), do: skill_id)
    }
  end

  def snapshot(_entity, _hand, _get_template), do: %{caster_attack_skill: nil, weapon_skill_id: nil}

  defp weapon_skill(character, :mainhand, get_template) do
    if Disarm.unarmed?(character),
      do: Skills.unarmed_skill(),
      else: Skills.main_hand_weapon_skill(character.player, get_template)
  end

  defp weapon_skill(character, :offhand, get_template), do: Skills.off_hand_weapon_skill(character.player, get_template)

  defp weapon_skill(%{unit: %{ranged_weapon: %{class: 2, subclass: subclass}}}, :ranged, _get_template),
    do: Skills.weapon_skill_for_subclass(subclass)

  defp weapon_skill(character, :ranged, get_template), do: Skills.ranged_weapon_skill(character.player, get_template)

  defp trainable_form?(form), do: form in [nil, 0] or form in Spell.stance_like_forms()

  def resolve(defender, attack, outcome, opts \\ []) do
    if not Core.dead?(defender) and outcome in @training_outcomes and Map.get(attack, :skill_training?, true) do
      {advance_defense(defender, attack, opts), weapon_events(defender, attack)}
    else
      {defender, []}
    end
  end

  defp advance_defense(%Character{} = defender, attack, opts) do
    if Map.get(attack, :caster_player?, false) or player_guid?(Map.get(attack, :caster_owner_guid)) do
      defender
    else
      opts = Keyword.put(opts, :mob_level, Map.get(attack, :caster_level) || defender.unit.level || 1)
      advance(defender, Skills.defense_skill(), opts)
    end
  end

  defp advance_defense(defender, _attack, _opts), do: defender

  defp weapon_events(defender, %{caster: caster, weapon_skill_id: skill_id}) when is_integer(skill_id) do
    if player_guid?(caster) and not player_controlled?(defender),
      do: [%Effects.AdvanceCombatSkill{target_guid: caster, skill_id: skill_id}],
      else: []
  end

  defp weapon_events(_defender, _attack), do: []

  defp player_controlled?(%Character{}), do: true
  defp player_controlled?(%{internal: %{pet: %{owner_guid: guid}}}), do: player_guid?(guid)
  defp player_controlled?(%{internal: %{totem: %{owner_guid: guid}}}), do: player_guid?(guid)
  defp player_controlled?(_entity), do: false

  defp player_guid?(guid) when is_integer(guid) and guid > 0, do: Guid.entity_type(guid) == :player
  defp player_guid?(_guid), do: false

  def advance(entity, skill_id, opts \\ [])

  def advance(%Character{unit: unit, player: player} = character, skill_id, opts) do
    opts =
      opts
      |> Keyword.put_new(:mob_level, unit.level || 1)
      |> Keyword.merge(
        player_level: unit.level || 1,
        intellect: unit.intellect || 0,
        defense?: skill_id == Skills.defense_skill()
      )

    case Skills.combat_skill_up(player.skills, skill_id, opts) do
      {:gained, skills} ->
        %{character | player: %{player | skills: skills}}
        |> CombatRatings.sync()
        |> Core.mark_broadcast_update()

      :unchanged ->
        character
    end
  end

  def advance(entity, _skill_id, _opts), do: entity
end
