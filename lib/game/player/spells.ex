defmodule ThistleTea.Game.Player.Spells do
  @moduledoc """
  Boundary for teaching a player spells: applies rank supersession, rebuilds
  the spellbook, persists the character, and notifies the client of each
  learned or superseded spell. Aura cancellation uses the owning player's
  publication path so derived metadata and visibility change with the aura.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.TrainerSpell
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.CombatRatings
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Proficiency
  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Entity.Logic.SpellBook
  alias ThistleTea.Game.Entity.Logic.SpellRemoval
  alias ThistleTea.Game.Entity.Logic.SpellSkills
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.Environment
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Loader.Skill, as: SkillLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @battle_stance_spell_id 2457
  @warrior_class 1

  def cancel_aura(%{character: %Character{} = character} = state, spell_id) do
    character = maybe_cancel_channel(character, spell_id)
    {character, events} = AuraLogic.cancel_spell(character, spell_id, Time.now())
    character = Effects.enqueue(character, events)
    PlayerServer.maybe_broadcast_update(%{state | character: character})
  end

  def cancel_aura(state, _spell_id), do: state

  defp maybe_cancel_channel(%Character{internal: %{casting: %Cast{spell: %Spell{id: id} = spell}}} = character, id) do
    if Spell.attribute?(spell, :channeled), do: Casting.cancel(character), else: character
  end

  defp maybe_cancel_channel(character, _spell_id), do: character

  def learn(%Character{} = character, spell_ids) do
    case prepare(character, spell_ids) do
      {:ok, character, events} ->
        CharacterStore.put(character)
        notify_learned(character, events)
        {:ok, character, events}

      :already_known ->
        :already_known
    end
  end

  def prepare(%Character{} = character, spell_ids) do
    case learn_spells(character, spell_ids, MapSet.new()) do
      {_character, []} ->
        :already_known

      {character, events} ->
        character = character |> apply_passives(Time.now()) |> Core.mark_broadcast_update()
        {:ok, character, events}
    end
  end

  def notify_learned(%Character{} = character, events) do
    Enum.each(events, &send_event_packet/1)
    send_proficiencies(character)
  end

  defp learn_spells(%Character{internal: internal} = character, spell_ids, attempted) do
    spell_ids = Enum.reject(spell_ids, &MapSet.member?(attempted, &1))
    attempted = MapSet.union(attempted, MapSet.new(spell_ids))
    existing_ids = internal.spells || []
    superseded_by = SpellLoader.superseded_by_map(existing_ids ++ spell_ids)

    case SpellBook.learn(existing_ids, spell_ids, superseded_by) do
      {_all_ids, []} ->
        {character, []}

      {all_ids, events} ->
        spellbook = SpellLoader.build_spellbook(all_ids)

        character =
          %{character | internal: %{internal | spells: all_ids, spellbook: spellbook}}
          |> learn_skills(all_ids -- existing_ids)

        {character, reward_events} = learn_spells(character, skill_rewards(character), attempted)
        {character, events ++ reward_events}
    end
  end

  defp learn_skills(%Character{unit: unit, player: player, internal: internal} = character, learned_ids) do
    new_skills = SkillLoader.initial_skills(internal.spells, unit.race, unit.class, unit.level)
    {new_skills, forgotten} = Skills.restore(new_skills, internal.forgotten_skills)
    grants = SpellSkills.grants(Map.take(internal.spellbook, learned_ids))
    skills = (player.skills || %{}) |> Skills.merge(new_skills) |> SpellSkills.learn(grants)
    %{character | player: %{player | skills: skills}, internal: %{internal | forgotten_skills: forgotten}}
  end

  def learn_training(%Character{} = character, %TrainerSpell{} = training) do
    skills = Skills.learn_rank(character.player.skills, training.skill_id, training.skill_max)
    character = %{character | player: %{character.player | skills: skills}}
    learn(character, [training.learned_spell_id])
  end

  defp skill_rewards(%Character{player: player, unit: unit}) do
    player.skills
    |> Enum.flat_map(fn {id, skill} -> SkillLoader.reward_spells(id, skill.value, unit.race, unit.class) end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  def unlearn(%Character{} = character, spell_ids, now) when is_list(spell_ids) and is_integer(now) do
    previous = SpellSkills.grants(character.internal.spellbook || %{})
    current = SpellSkills.grants(Map.drop(character.internal.spellbook || %{}, spell_ids))
    lost_skills = Map.keys(previous) -- Map.keys(current)
    associated = Enum.flat_map(lost_skills, &SkillLoader.spells/1)
    spell_ids = Enum.uniq(spell_ids ++ Enum.filter(character.internal.spells || [], &(&1 in associated)))
    character = SpellRemoval.remove(character, spell_ids, now)
    CharacterStore.put(character)
    notify_unlearned(character, spell_ids)
    character
  end

  def notify_unlearned(%Character{} = character, spell_ids) do
    Enum.each(spell_ids, &Network.send_packet(%Message.SmsgRemovedSpell{spell_id: &1}))
    send_proficiencies(character)
  end

  def apply_passives(%Character{internal: %{spellbook: spellbook}} = character, now)
      when is_map(spellbook) and is_integer(now) do
    spellbook
    |> Map.values()
    |> Enum.filter(&(passive_aura_spell?(&1) and Environment.validate(&1, character.internal.outdoors?) == :ok))
    |> Enum.reduce(character, fn spell, character ->
      if AuraLogic.has_spell?(character, spell.id) do
        character
      else
        apply_aura_spell(character, spell, now)
      end
    end)
    |> CombatRatings.sync()
  end

  def apply_passives(character, _now), do: character

  def apply_default_auras(
        %Character{unit: %Unit{class: @warrior_class}, internal: %Internal{spellbook: spellbook}} = character,
        now
      )
      when is_map(spellbook) and is_integer(now) do
    if AuraLogic.has_aura?(character, :mod_shapeshift) do
      character
    else
      case Map.get(spellbook, @battle_stance_spell_id) do
        %Spell{} = spell -> apply_aura_spell(character, spell, now)
        _missing -> character
      end
    end
  end

  def apply_default_auras(character, _now), do: character

  defp passive_aura_spell?(%Spell{} = spell) do
    Spell.attribute?(spell, :passive) and (spell.stances || 0) == 0 and Spell.aura_effects(spell) != []
  end

  defp apply_aura_spell(%Character{} = character, %Spell{} = spell, now) do
    {character, events} =
      AuraLogic.apply_spell(character, character.object.guid, character.unit.level || 1, spell, now)

    Effects.enqueue(character, events)
  end

  def send_proficiencies(%Character{} = character) do
    prof = Proficiency.from_character(character)

    Network.send_packet(%Message.SmsgSetProficiency{
      item_class: Proficiency.item_class_weapon(),
      subclass_mask: prof.weapon_mask
    })

    Network.send_packet(%Message.SmsgSetProficiency{
      item_class: Proficiency.item_class_armor(),
      subclass_mask: prof.armor_mask
    })
  end

  defp send_event_packet({:learned, spell_id}) do
    Network.send_packet(%Message.SmsgLearnedSpell{spell_id: spell_id})
  end

  defp send_event_packet({:superseded, old_id, new_id}) do
    Network.send_packet(%Message.SmsgSupercededSpell{old_spell_id: old_id, new_spell_id: new_id})
  end

  defp send_event_packet({:removed, spell_id}) do
    Network.send_packet(%Message.SmsgRemovedSpell{spell_id: spell_id})
  end
end
