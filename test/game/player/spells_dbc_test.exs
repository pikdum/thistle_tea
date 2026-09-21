defmodule ThistleTea.Game.Player.SpellsDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.TrainerSpell
  alias ThistleTea.Game.Entity.Logic.Breathing
  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Player.Spells
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Loader.Skill

  @moduletag :dbc_db

  setup_all do
    Skill.load_all()
  end

  describe "learn/2" do
    setup [:character]

    test "activates passive breathing immediately and stores the resulting character", %{character: character} do
      assert {:ok, learned, [{:learned, 5227}]} = Spells.learn(character, [5227])
      assert Enum.map(learned.unit.auras, & &1.spell.id) == [5227]
      assert CharacterStore.get(learned.id) == learned
      assert Breathing.update(learned, 10.0, 1000).internal.breath.duration == 240_000
      assert Spells.learn(learned, [5227]) == :already_known
    end

    test "does not automatically cast an active spell", %{character: character} do
      assert {:ok, learned, [{:learned, 5697}]} = Spells.learn(character, [5697])
      assert learned.unit.auras == []
    end

    test "direct profession learning grants its rank, tools and starting recipes", %{character: character} do
      assert {:ok, learned, events} = Spells.learn(character, [2575])
      assert %{value: 1, max: 75, step: 1, range: :tier} = learned.player.skills[186]
      assert Skills.free_profession_slots(learned.player.skills) == 1
      assert Enum.all?([2575, 2580, 2656, 2657], &(&1 in learned.internal.spells))
      assert {:learned, 2657} in events
      refute 2658 in learned.internal.spells
      assert CharacterStore.get(learned.id) == learned
      assert Spells.learn(learned, [2575]) == :already_known

      learned = put_in(learned.player.skills[186].value, 50)
      assert {:ok, upgraded, _events} = Spells.learn(learned, [2576])
      assert %{value: 50, max: 150, step: 2} = upgraded.player.skills[186]
      assert upgraded.player.skills[186].slot == learned.player.skills[186].slot
      assert CharacterStore.get(upgraded.id) == upgraded
    end

    test "secondary skills and riding use their learned rank values", %{character: character} do
      assert {:ok, learned, _events} = Spells.learn(character, [2550, 3273, 7620, 33_388])
      for id <- [185, 129, 356], do: assert(%{value: 1, max: 75, step: 1} = learned.player.skills[id])
      assert %{value: 75, max: 75, step: 1} = learned.player.skills[762]
      assert Skills.free_profession_slots(learned.player.skills) == 2
      assert Enum.all?([2538, 3275], &(&1 in learned.internal.spells))
      assert {:ok, upgraded, _events} = Spells.learn(learned, [33_391])
      assert %{value: 150, max: 150, step: 2} = upgraded.player.skills[762]
    end

    test "removing the granting profession clears its recipes and relearning resets progress", %{character: character} do
      assert {:ok, learned, _events} = Spells.learn(character, [2575, 2550])
      learned = put_in(learned.player.skills[186].value, 60)
      removed = Spells.unlearn(learned, [2575], 1_000)
      refute Map.has_key?(removed.player.skills, 186)
      refute Map.has_key?(removed.internal.forgotten_skills, 186)
      refute Enum.any?([2575, 2580, 2656, 2657], &(&1 in removed.internal.spells))
      assert removed.player.skills[185].value == 1
      assert 2538 in removed.internal.spells
      assert Skills.free_profession_slots(removed.player.skills) == 2
      assert CharacterStore.get(removed.id) == removed

      assert {:ok, relearned, _events} = Spells.learn(removed, [2575])
      assert %{value: 1, max: 75, step: 1} = relearned.player.skills[186]
      assert 2657 in relearned.internal.spells
    end

    test "publishes language skill changes on learning and removal", %{character: character} do
      character = %{character | internal: %{character.internal | broadcast_update?: false}}
      assert {:ok, learned, [{:learned, 672}]} = Spells.learn(character, [672])
      assert learned.internal.broadcast_update?
      assert %{value: 300, max: 300, range: :language} = learned.player.skills[111]
      assert CharacterStore.get(learned.id) == learned

      learned = %{learned | internal: %{learned.internal | broadcast_update?: false}}
      removed = Spells.unlearn(learned, [672], 1_000)
      assert removed.internal.broadcast_update?
      refute Map.has_key?(removed.player.skills, 111)
      assert CharacterStore.get(removed.id) == removed
    end
  end

  describe "learn_training/2" do
    setup [:character]

    test "teaches profession starter spells and preserves skill on rank upgrades", %{character: character} do
      apprentice = %TrainerSpell{learned_spell_id: 7411, skill_id: 333, skill_max: 75}
      assert {:ok, learned, events} = Spells.learn_training(character, apprentice)
      assert Enum.sort(Enum.map(events, &elem(&1, 1))) == [7411, 7418, 7421, 7428, 13_262]
      assert learned.player.skills[333].value == 1
      assert learned.player.skills[333].max == 75
      assert Map.has_key?(learned.internal.spellbook, 13_262)
      refute Map.has_key?(learned.internal.spellbook, 7420)

      learned = put_in(learned.player.skills[333].value, 50)
      journeyman = %TrainerSpell{learned_spell_id: 7412, skill_id: 333, skill_max: 150}
      assert {:ok, upgraded, events} = Spells.learn_training(learned, journeyman)
      assert upgraded.player.skills[333].value == 50
      assert upgraded.player.skills[333].max == 150
      refute {:learned, 13_262} in events
      assert CharacterStore.get(upgraded.id) == upgraded
    end

    test "ordinary spell training does not add profession skills", %{character: character} do
      assert {:ok, learned, [{:learned, 5697}]} =
               Spells.learn_training(character, %TrainerSpell{learned_spell_id: 5697})

      refute Map.has_key?(learned.player.skills, 333)
    end
  end

  defp character(_context) do
    character =
      CharacterStore.create(%Character{
        id: 0,
        object: %Object{guid: 0},
        player: %Player{skills: %{}},
        unit: %Unit{race: 1, class: 8, level: 10, health: 100, max_health: 100, auras: []},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{spells: [], spellbook: %{}}
      })

    on_exit(fn -> :ets.delete(CharacterStore, character.id) end)
    [character: character]
  end
end
