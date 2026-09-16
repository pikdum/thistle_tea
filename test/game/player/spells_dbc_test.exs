defmodule ThistleTea.Game.Player.SpellsDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
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
