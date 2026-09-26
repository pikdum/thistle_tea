defmodule ThistleTea.Game.Player.QuestRewardsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Logic.QuestLog
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.QuestRewards
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata

  setup [:character]

  describe "credit_event/2" do
    test "rewards a hidden flag once without consuming a log slot or announcing it", %{state: state, quest: quest} do
      full = Map.new(0..19, &{&1, %QuestLog.Entry{quest_id: &1 + 1}})
      state = %{state | character: %{state.character | player: %{state.character.player | quest_log: full}}}
      rewarded = Quests.credit_event(state, quest.id)
      assert MapSet.member?(rewarded.character.player.rewarded_quests, quest.id)
      assert rewarded.character.player.quest_log == full
      assert rewarded.character.player.coinage == 123
      assert CharacterStore.get(state.guid).player == rewarded.character.player
      assert Quests.credit_event(rewarded, quest.id) == rewarded
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgQuestgiverQuestComplete{}}}
    end

    test "removes an accepted flag while ordinary unaccepted quests remain untouched", %{state: state, quest: quest} do
      {:ok, log} = QuestLog.add(%{}, quest.id)
      state = %{state | character: %{state.character | player: %{state.character.player | quest_log: log}}}
      rewarded = Quests.credit_event(state, quest.id)
      refute QuestLog.active?(rewarded.character.player.quest_log, quest.id)
      :ets.insert(QuestLoader, {{:quest, quest.id}, %{quest | flags: 0}})
      empty = %{state | character: %{state.character | player: %Player{}}}
      assert Quests.credit_event(empty, quest.id) == empty
    end

    test "rejects a low-level flag without rewards or casts", %{state: state, quest: quest} do
      :ets.insert(QuestLoader, {{:quest, quest.id}, %{quest | min_level: 61}})
      assert Quests.credit_event(state, quest.id) == state
      refute_receive {:"$gen_cast", {:trigger_spell, _, _, _}}
    end
  end

  describe "cast_spell/3" do
    test "prefers the hidden cast reward and dispatches self effects to the player owner", %{state: state, quest: quest} do
      Entity.register(state.guid)
      spell = cache_spell(%Spell{id: quest.id, effects: [%Effect{type: :dummy, implicit_target_a: :caster}]})
      quest = %{quest | reward_spell: 999, reward_spell_cast: spell.id}
      assert QuestRewards.cast_spell(state, quest, Guid.from_low_guid(:mob, 1, 1)) == state
      assert_receive {:"$gen_cast", {:trigger_spell, id, target, []}}
      assert id == spell.id
      assert target == state.guid
    end

    test "routes teaching item creation and friendly-target rewards through the questgiver", %{
      state: state,
      quest: quest
    } do
      npc = Guid.from_low_guid(:mob, 1, state.guid)
      Entity.register(npc)

      for effect <- [
            %Effect{type: :learn_spell},
            %Effect{type: :create_item},
            %Effect{type: :apply_aura, implicit_target_a: :any_unit},
            %Effect{type: :apply_aura, implicit_target_a: :target_ally}
          ] do
        spell = cache_spell(%Spell{id: quest.id, effects: [effect]})
        QuestRewards.cast_spell(state, %{quest | reward_spell: spell.id}, npc)
        assert_receive {:"$gen_cast", {:trigger_spell, id, target, []}}
        assert id == spell.id
        assert target == state.guid
      end
    end

    test "game-object reward spells use the player as caster", %{state: state, quest: quest} do
      Entity.register(state.guid)
      spell = cache_spell(%Spell{id: quest.id, effects: [%Effect{type: :learn_spell}]})
      QuestRewards.cast_spell(state, %{quest | reward_spell: spell.id}, Guid.from_low_guid(:game_object, 1, 1))
      assert_receive {:"$gen_cast", {:trigger_spell, id, target, []}}
      assert id == spell.id
      assert target == state.guid
    end
  end

  defp cache_spell(spell) do
    :ets.insert(SpellLoader, {{:spell, spell.id}, spell})
    spell
  end

  defp character(_context) do
    id = System.unique_integer([:positive, :monotonic])
    quest = %Quest{id: 98_500_000 + id, flags: 0x400, min_level: 60, reward_money: 123}
    :ets.insert(QuestLoader, {{:quest, quest.id}, quest})

    character = %Character{
      id: id,
      object: %Object{guid: id},
      player: %Player{coinage: 0},
      unit: %Unit{level: 60, race: 1, class: 1, health: 100, max_health: 100, auras: []},
      internal: %Internal{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    CharacterStore.put(character)

    on_exit(fn ->
      :ets.delete(QuestLoader, {:quest, quest.id})
      :ets.delete(SpellLoader, {:spell, quest.id})
      :ets.delete(CharacterStore, id)
      Metadata.delete(id)
    end)

    %{state: %{guid: id, character: character}, quest: quest}
  end
end
