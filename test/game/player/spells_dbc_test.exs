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
  alias ThistleTea.Game.Player.Spells
  alias ThistleTea.Game.World.CharacterStore

  @moduletag :dbc_db

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
