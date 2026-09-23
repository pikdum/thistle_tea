defmodule ThistleTea.Game.World.Loader.ElementalCombatDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  setup [:target]

  describe "receive_attack/4" do
    test "real Fire Ward absorbs fire melee and expires through the shared aura lifecycle", %{target: target} do
      {warded, _events} = Aura.apply_spell(target, 1, 50, SpellLoader.load(543), 0)
      assert Aura.flat_amount(warded, :school_absorb) == 165
      {warded, events} = Combat.receive_attack(warded, attack(), 1_000, roll: 9_999, resist_roll: 99)
      assert warded.unit.health == 1_000
      assert Aura.flat_amount(warded, :school_absorb) == 65
      assert Enum.any?(events, &match?(%Effects.AttackerStateUpdate{damage: 0, attack: %{absorb: 100}}, &1))
      {expired, _events} = Aura.expire_due(warded, 30_000)
      {damaged, _events} = Combat.receive_attack(expired, attack(), 30_001, roll: 9_999, resist_roll: 99)
      assert damaged.unit.health == 900
    end

    test "real Dampen and Amplify Magic modify elemental swings", %{target: target} do
      for {spell_id, health} <- [{604, 910}, {1008, 885}] do
        {buffed, _events} = Aura.apply_spell(target, 1, 50, SpellLoader.load(spell_id), 0)
        {damaged, _events} = Combat.receive_attack(buffed, attack(), 1_000, roll: 9_999, resist_roll: 99)
        assert damaged.unit.health == health
      end
    end
  end

  defp attack, do: %{caster: 2, caster_level: 50, damage: 100, spell_school_mask: 4}

  defp target(_context) do
    %{
      target: %Character{
        object: %Object{guid: 1},
        unit: %Unit{health: 1_000, max_health: 1_000, level: 50, auras: []},
        player: %Player{},
        internal: %Internal{},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }
    }
  end
end
