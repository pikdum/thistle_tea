defmodule ThistleTea.Game.Player.LiquidSpellsDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.LiquidSpells, as: LiquidSpellLogic
  alias ThistleTea.Game.Player.LiquidSpells
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Terrain.Liquid

  @moduletag :dbc_db

  describe "context/2" do
    test "loads the real slime spell with its stat penalty and nature damage" do
      character = %Character{
        object: %Object{guid: 98_029},
        player: %Player{flags: 0},
        unit: %Unit{health: 1000, max_health: 1000, level: 60, base_strength: 100, strength: 100, auras: []},
        internal: %Internal{},
        movement_block: %MovementBlock{position: {0.0, 0.0, -1.0, 0.0}}
      }

      liquid = %Liquid{entry: 21, flags: 4, surface: 0.0, floor: -10.0}

      assert %CastContext{spell: %Spell{id: 28_801, school: :nature}, triggered?: true} =
               context =
               LiquidSpells.context(character, liquid)

      entered = LiquidSpellLogic.reconcile(character, context, 1000)
      assert entered.unit.strength == 10
      assert [holder] = entered.unit.auras
      assert holder.negative?
      assert Enum.any?(holder.auras, &match?(%{type: :periodic_damage, amount: 100, amplitude_ms: 2000}, &1))
      assert Enum.any?(holder.auras, &match?(%{type: :mod_total_stat_percent, amount: -90, misc_value: -1}, &1))
      assert LiquidSpells.context(character, %{liquid | entry: 4}) == nil
    end
  end
end
