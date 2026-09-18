defmodule ThistleTea.Game.World.Loader.HealingReceivedDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.HealingReceived
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "real suppression spells apply their DBC magnitudes" do
      for {id, expected} <- [{9_035, 160}, {19_716, 50}, {23_230, 100}, {25_646, 180}] do
        spell = SpellLoader.load(id)
        entity = %Mob{unit: %Unit{health: 100, max_health: 1_000, auras: []}}
        {entity, _events} = Aura.apply_spell(entity, 2, 60, spell, 0)
        assert HealingReceived.amount(entity, 200) == expected
      end
    end

    test "Mortal Wound reaches complete suppression at ten stacks" do
      spell = SpellLoader.load(25_646)
      assert spell.stack_amount == 10
      entity = %Mob{unit: %Unit{health: 100, max_health: 1_000, auras: []}}

      entity =
        Enum.reduce(1..10, entity, fn _, entity ->
          {entity, _events} = Aura.apply_spell(entity, 2, 60, spell, 0)
          entity
        end)

      assert HealingReceived.amount(entity, 200) == 0
    end
  end
end
