defmodule ThistleTea.Game.Entity.Logic.CombatWeapon do
  @moduledoc """
  Usable weapon identities and skill snapshots from canonical equipment inputs.
  Natural weapons and disarm are resolved without loading item data at attack time.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Disarm
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Spell

  @natural_forms [1, 2, 3, 4, 5, 8]

  def usable(entity, hand, get_template \\ nil)

  def usable(%{unit: %Unit{shapeshift_form: form}}, _hand, _get_template) when form in [1, 5, 8], do: nil

  def usable(%{unit: %Unit{}} = entity, :mainhand, get_template) do
    if not Disarm.unarmed?(entity) and not broken?(entity, :mainhand), do: equipped(entity, :mainhand, get_template)
  end

  def usable(entity, hand, get_template) do
    if not broken?(entity, hand), do: equipped(entity, hand, get_template)
  end

  defp broken?(%{player: %Player{broken_equipment: slots}}, hand) when is_list(slots), do: hand in slots
  defp broken?(_entity, _hand), do: false

  def equipped(entity, hand, get_template \\ nil)

  def equipped(%Character{player: player}, hand, get_template) when is_function(get_template, 1) do
    with entry when is_integer(entry) and entry > 0 <- Inventory.equipment_entry(player, hand, include_broken: true),
         %{class: 2} = weapon <- get_template.(entry) do
      weapon
    else
      _ -> nil
    end
  end

  def equipped(%{unit: %Unit{mainhand_weapon: weapon}}, :mainhand, _get_template), do: weapon
  def equipped(%{unit: %Unit{offhand_weapon: weapon}}, :offhand, _get_template), do: weapon
  def equipped(%{unit: %Unit{ranged_weapon: weapon}}, :ranged, _get_template), do: weapon
  def equipped(_entity, _hand, _get_template), do: nil

  def skill_snapshot(entity, hand, get_template \\ nil)

  def skill_snapshot(%{unit: %Unit{} = unit, player: %Player{} = player} = character, hand, get_template) do
    skill_id = skill_id(usable(character, hand, get_template), hand)
    {temporary, permanent} = Map.get(Skills.bonuses(character), skill_id, {0, 0})
    maximum = Skills.max_for_level(unit.level || 1)

    value =
      cond do
        is_nil(skill_id) -> 0
        unit.shapeshift_form in @natural_forms -> maximum
        true -> max(Skills.value(player.skills, skill_id, maximum) + temporary + permanent, 0)
      end

    %{
      caster_attack_skill: value,
      weapon_skill_id: if(trainable_form?(unit.shapeshift_form) and skill_id != Skills.fishing_skill(), do: skill_id)
    }
  end

  def skill_snapshot(_entity, _hand, _get_template), do: %{caster_attack_skill: nil, weapon_skill_id: nil}

  defp skill_id(%{class: 2, subclass: subclass}, hand) do
    Skills.weapon_skill_for_subclass(subclass) || skill_id(nil, hand)
  end

  defp skill_id(_weapon, :mainhand), do: Skills.unarmed_skill()
  defp skill_id(_weapon, _hand), do: nil

  defp trainable_form?(form), do: form in [nil, 0] or form in Spell.stance_like_forms()
end
