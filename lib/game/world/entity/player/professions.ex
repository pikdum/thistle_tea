defmodule ThistleTea.Game.World.Entity.Player.Professions do
  @moduledoc """
  Validates skill abandonment against the cached DBC flags, commits the
  planned character and inventory changes, and publishes spell and quest loss.
  """

  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Inventory.ChangeSet
  alias ThistleTea.Game.Core.Profession.Professions, as: ProfessionsCore
  alias ThistleTea.Game.Core.Quest.QuestLog
  alias ThistleTea.Game.Core.Spell.Cast
  alias ThistleTea.Game.Core.Spell.SpellRemoval
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.World.Entity.Player, as: PlayerServer
  alias ThistleTea.Game.World.Entity.Player.InventoryUpdate
  alias ThistleTea.Game.World.Entity.Player.Quests
  alias ThistleTea.Game.World.Entity.Player.Spellcasting
  alias ThistleTea.Game.World.Entity.Player.Spells
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader
  alias ThistleTea.Game.World.Loader.Skill, as: SkillLoader

  def unlearn(%{character: %Character{} = character} = state, skill_id) do
    with true <- SkillLoader.unlearnable?(skill_id, character.unit.race, character.unit.class),
         {:ok, changes} <-
           ProfessionsCore.plan(
             character.player,
             skill_id,
             known_quests(character),
             &ItemStore.get/1
           ) do
      commit(state, skill_id, changes)
    else
      _invalid -> state
    end
  end

  def unlearn(state, _skill_id), do: state

  defp commit(state, skill_id, changes) do
    previous = state.character
    associated = SkillLoader.spells(skill_id)
    removed = Enum.filter(previous.internal.spells || [], &(&1 in associated))
    state = cancel_removed_cast(state, removed)
    character = state.character

    character = %{
      character
      | player: changes.player,
        internal: %{character.internal | forgotten_skills: Map.delete(character.internal.forgotten_skills, skill_id)}
    }

    character = SpellRemoval.remove(character, removed, Time.now())
    changes = ChangeSet.put_player(changes, character.player)
    state = InventoryUpdate.apply(%{state | character: %{character | player: previous.player}}, {:ok, changes})
    Spells.notify_unlearned(state.character, removed)
    Quests.sync_character_change(previous, state.character)
    PlayerServer.maybe_broadcast_update(%{state | character: Entity.mark_broadcast_update(state.character)})
  end

  defp known_quests(%Character{player: player}) do
    active = Enum.map(QuestLog.active_entries(player.quest_log), & &1.quest_id)

    (active ++ MapSet.to_list(player.rewarded_quests))
    |> Enum.uniq()
    |> Enum.map(&QuestLoader.get/1)
    |> Enum.reject(&is_nil/1)
  end

  defp cancel_removed_cast(%{character: %{internal: %{casting: %Cast{} = cast}}} = state, removed) do
    if Cast.spell_id(cast) in removed, do: Spellcasting.cancel(state), else: state
  end

  defp cancel_removed_cast(state, _removed), do: state
end
