defmodule ThistleTea.Game.Entity.Logic.PetTraining do
  @moduledoc """
  Atomic pet ability purchases: eligibility, rank credit, training balance,
  passive aura replacement, and active spell projection over supplied data.
  """

  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.CreatureSpell
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.PetAbility
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.PetLoyalty
  alias ThistleTea.Game.Entity.Logic.PetSpellModifiers
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  def training_effect?(%Effect{type: :learn_pet_spell}), do: true
  def training_effect?(%Effect{type: :learn_spell, implicit_target_a: :pet}), do: true
  def training_effect?(%Effect{type: :learn_spell, implicit_target_b: :pet}), do: true
  def training_effect?(_effect), do: false

  def ability_id(%Spell{effects: effects}) do
    case Enum.find(effects, &training_effect?/1) do
      %Effect{trigger_spell_id: id} -> id
      _ -> nil
    end
  end

  def validate(
        %Mob{internal: %{pet: %Pet{owner_guid: owner, kind: :hunter, broken?: false}}} = pet,
        owner,
        %Spell{} = teaching,
        abilities,
        family_skill
      ) do
    with false <- Core.dead?(pet),
         %PetAbility{} = ability <- Map.get(abilities, ability_id(teaching)) do
      validate_ability(pet, teaching, ability, abilities, family_skill)
    else
      true -> {:error, :targets_dead}
      _ -> {:error, :not_known}
    end
  end

  def validate(_pet, _owner, _teaching, _abilities, _family_skill), do: {:error, :no_pet}

  def learn(%Mob{} = pet, owner, %Spell{} = teaching, abilities, family_skill, now) do
    with :ok <- validate(pet, owner, teaching, abilities, family_skill) do
      ability = Map.fetch!(abilities, ability_id(teaching))
      spell = ability.spell
      previous = same_chain(pet, spell, abilities)
      cost = cost(pet, ability, abilities)
      {pet, removed} = Aura.remove_spells(pet, Enum.map(previous, & &1.id), now)
      spellbook = pet.internal.spellbook |> Map.drop(Enum.map(previous, & &1.id)) |> Map.put(spell.id, spell)
      control = replace_controls(pet.internal.pet, previous, spell, pet.internal.spellbook)
      creature = %{pet.internal.creature | spells: action_spells(spellbook)}
      pet = %{pet | internal: %{pet.internal | spellbook: spellbook, pet: control, creature: creature}}
      pet = pet |> PetLoyalty.spend_training_points(cost) |> Effects.enqueue(removed)
      pet = if Spell.attribute?(spell, :passive), do: apply_passive(pet, spell, now), else: pet
      {:ok, Core.mark_broadcast_update(pet)}
    end
  end

  def action_spells(spellbook) do
    spellbook
    |> Map.values()
    |> Enum.reject(&Spell.attribute?(&1, :passive))
    |> Enum.sort_by(& &1.id)
    |> Enum.map(fn spell ->
      %CreatureSpell{spell_id: spell.id, cast_target: if(Spell.harmful?(spell), do: :victim, else: :self)}
    end)
  end

  def restore_passives(%Mob{} = pet, now) do
    pet.internal.spellbook
    |> Map.values()
    |> Enum.filter(&Spell.attribute?(&1, :passive))
    |> Enum.sort_by(& &1.id)
    |> Enum.reduce(pet, &apply_passive(&2, &1, now))
  end

  defp validate_ability(pet, teaching, %PetAbility{spell: spell, skills: skills} = ability, abilities, family_skill) do
    cond do
      not eligible_family?(skills, family_skill) -> {:error, :bad_targets}
      known_rank?(pet, spell, abilities) -> {:error, :spell_learned}
      required_level(teaching, spell) > pet.unit.level -> {:error, :lowlevel}
      too_many_active?(pet, spell, abilities) -> {:error, :too_many_skills}
      insufficient_points?(pet, cost(pet, ability, abilities)) -> {:error, :training_points}
      true -> :ok
    end
  end

  defp eligible_family?(skills, family_skill), do: 270 in skills or family_skill in skills
  defp required_level(teaching, spell), do: max(teaching.spell_level || 0, spell.spell_level || 0)

  defp known_rank?(pet, spell, abilities) do
    Enum.any?(same_chain(pet, spell, abilities), &((&1.rank || 1) >= (spell.rank || 1)))
  end

  defp cost(pet, %PetAbility{spell: spell, cost: total}, abilities) do
    spent =
      pet
      |> same_chain(spell, abilities)
      |> Enum.map(fn previous ->
        case Map.get(abilities, previous.id) do
          %PetAbility{cost: cost} -> cost
          _ -> 0
        end
      end)
      |> Enum.max(fn -> 0 end)

    total - spent
  end

  defp insufficient_points?(_pet, 0), do: false
  defp insufficient_points?(pet, cost), do: cost < 0 or pet.internal.pet.training_points < cost

  defp too_many_active?(pet, spell, abilities) do
    active = Enum.reject([spell | known_spells(pet, abilities)], &Spell.attribute?(&1, :passive))
    not Spell.attribute?(spell, :passive) and length(Enum.uniq_by(active, &chain/1)) > 4
  end

  defp same_chain(pet, spell, abilities), do: Enum.filter(known_spells(pet, abilities), &(chain(&1) == chain(spell)))

  defp known_spells(pet, abilities) do
    Enum.map(Map.values(pet.internal.spellbook), fn spell ->
      case Map.get(abilities, spell.id) do
        %PetAbility{spell: canonical} -> canonical
        _ -> spell
      end
    end)
  end

  defp chain(%Spell{first_in_chain: first, id: id}), do: first || id

  defp apply_passive(pet, spell, now) do
    PetSpellModifiers.apply_passive(pet, spell, now)
  end

  defp replace_controls(%Pet{} = pet, previous, spell, spellbook) do
    ids = Enum.map(previous, & &1.id)
    enabled? = Enum.any?(ids, &MapSet.member?(pet.autocast, &1))
    autocast = Enum.reduce(ids, pet.autocast, &MapSet.delete(&2, &1))
    autocast = if enabled?, do: MapSet.put(autocast, spell.id), else: autocast

    action_bar =
      pet
      |> existing_action_bar(spellbook)
      |> Map.new(fn {slot, {id, type}} ->
        {slot, {if(id in ids, do: spell.id, else: id), type}}
      end)
      |> insert_action(spell)

    %{pet | autocast: autocast, action_bar: action_bar}
  end

  defp existing_action_bar(pet, spellbook) do
    placed = MapSet.new(pet.action_bar, fn {_slot, {id, _type}} -> id end)

    defaults =
      spellbook
      |> action_spells()
      |> Enum.take(4)
      |> Enum.with_index(3)
      |> Map.new(fn {entry, slot} ->
        type = if MapSet.member?(pet.autocast, entry.spell_id), do: 0xC1, else: 0x81
        id = if MapSet.member?(placed, entry.spell_id), do: 0, else: entry.spell_id
        {slot, {id, type}}
      end)

    3..6 |> Map.new(&{&1, {0, 0x81}}) |> Map.merge(defaults) |> Map.merge(pet.action_bar)
  end

  defp insert_action(bar, spell) do
    if Spell.attribute?(spell, :passive) or Enum.any?(bar, fn {_slot, {id, _type}} -> id == spell.id end) do
      bar
    else
      case Enum.find(3..6, &(elem(Map.get(bar, &1, {0, 0x81}), 0) == 0)) do
        nil -> bar
        slot -> Map.put(bar, slot, {spell.id, 0x81})
      end
    end
  end
end
