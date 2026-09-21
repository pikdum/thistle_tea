defmodule ThistleTea.Game.Player.Teaching do
  @moduledoc "Commits teaching spells and skill steps with their recipe-book costs on the player owner."

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Inventory.Batch
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet
  alias ThistleTea.Game.Entity.Logic.ItemUse
  alias ThistleTea.Game.Entity.Logic.Proficiency
  alias ThistleTea.Game.Entity.Logic.SpellTeaching
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Reputation
  alias ThistleTea.Game.Player.Spells
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Skill, as: SkillLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  def validate(%Character{} = character, %Spell{} = spell, item_guid) do
    if SpellTeaching.spell?(spell) do
      with {:ok, taught} <- taught_spells(spell),
           :ok <- validate_book(character, spell, item_guid) do
        validate_unknown(character, taught, item_guid)
      end
    else
      :ok
    end
  end

  defp validate_unknown(character, taught, item_guid) do
    if is_integer(item_guid) and taught != [] and Enum.all?(taught, &known?(character, &1)),
      do: {:error, :spell_learned},
      else: :ok
  end

  def complete(%{character: %Character{} = character} = state, %Effects.TeachSpell{} = effect) do
    with false <- Core.dead?(character),
         :ok <- validate(character, effect.spell, effect.cast_item_guid),
         {:ok, changes} <- plan_costs(character, effect.spell, effect.cast_item_guid) do
      character = %{character | player: changes.player}
      {character, learned_events} = prepare(character, SpellTeaching.spell_ids(effect.spell))
      skills = SpellTeaching.apply_steps(character.player.skills, effect.skill_steps)
      character = %{character | player: %{character.player | skills: skills}}
      {character, reward_events} = prepare(character, skill_rewards(character, effect.skill_steps))
      changes = ChangeSet.put_player(changes, character.player)
      state = InventoryUpdate.apply(%{state | character: character}, {:ok, changes})
      Spells.notify_learned(state.character, learned_events ++ reward_events)
      state
    else
      true -> fail(state, effect.spell, :caster_dead)
      {:error, reason} -> fail(state, effect.spell, reason)
    end
  end

  defp prepare(character, ids) do
    case Spells.prepare(character, ids) do
      {:ok, character, events} -> {character, events}
      :already_known -> {Core.mark_broadcast_update(character), []}
    end
  end

  defp taught_spells(spell) do
    taught = Enum.map(SpellTeaching.spell_ids(spell), &SpellLoader.load/1)
    if Enum.all?(taught, &is_struct(&1, Spell)), do: {:ok, taught}, else: {:error, :not_known}
  end

  defp known?(character, taught) do
    taught.id in (character.internal.spells || []) or
      Enum.any?(character.internal.spellbook || %{}, fn {_id, known} ->
        Spell.stronger_rank_of_same_chain?(known, taught)
      end)
  end

  defp validate_book(_character, _spell, nil), do: :ok

  defp validate_book(character, spell, guid) do
    with {:ok, item, _index} <- owned_book(character, spell, guid),
         template = Item.template(item),
         :ok <- Inventory.can_use(character.unit, Proficiency.from_character(character), template, character.player),
         :ok <- Reputation.validate_item_requirement(character, template) do
      :ok
    else
      {:error, reason} when reason in [:item_gone, :no_charges_remain] -> {:error, reason}
      _requirement -> {:error, :low_castlevel}
    end
  end

  defp owned_book(character, spell, guid) do
    with {bag, slot} <- Inventory.find_position(character.player, guid, &ItemStore.get/1),
         false <- Inventory.bank_position?({bag, slot}),
         %Item{} = item <- ItemStore.get(guid),
         true <- item.item.owner == character.object.guid,
         {:ok, spell_id, index, _commit?} <- ItemUse.on_use_spell(item),
         true <- spell_id == spell.id do
      {:ok, item, index}
    else
      {:cast_error, _id, reason} -> {:error, reason}
      _invalid -> {:error, :item_gone}
    end
  end

  defp plan_costs(character, spell, item_guid) do
    reagents = if is_nil(item_guid) or character.internal.godmode, do: [], else: spell.reagents

    batch =
      Enum.reduce(reagents, Batch.new(character.player), fn {id, count}, batch -> Batch.remove(batch, id, count) end)

    with {:ok, batch} <- plan_book(batch, character, spell, item_guid),
         {:ok, changes} <- Inventory.plan(batch, &ItemStore.get/1) do
      {:ok, changes}
    else
      {:error, reason} when reason in [:item_gone, :no_charges_remain] -> {:error, reason}
      _missing -> {:error, :reagents}
    end
  end

  defp plan_book(batch, _character, _spell, nil), do: {:ok, batch}

  defp plan_book(batch, character, spell, guid) do
    with {:ok, item, index} <- owned_book(character, spell, guid) do
      ItemUse.plan(batch, item, index)
    end
  end

  defp skill_rewards(%Character{player: player, unit: unit}, steps) do
    Enum.flat_map(steps, fn {id, _step} ->
      SkillLoader.reward_spells(id, player.skills[id].value, unit.race, unit.class)
    end)
  end

  defp fail(state, spell, reason) do
    Network.send_packet(Message.SmsgCastResult.failure(spell.id, reason))
    state
  end
end
