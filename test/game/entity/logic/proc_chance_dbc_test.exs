defmodule ThistleTea.Game.Entity.Logic.ProcChanceDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Aura.ProcChance
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Proc
  alias ThistleTea.Game.Spell.ProcRule
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  setup [:character]

  describe "chance/4" do
    test "real ranged proc flags combine with their PPM rules", %{character: character} do
      shot = SpellLoader.load(75)

      for {id, ppm, expected} <- [{23_578, 2, 10}, {26_480, 10, 50}] do
        spell = %{SpellLoader.load(id) | proc_rule: %ProcRule{ppm_rate: ppm}}
        assert Proc.eligible?(spell, shot, :deal_ranged_attack, :normal)
        assert ProcChance.chance(character, spell, :outgoing, %{spell: shot}) == expected
        assert ProcChance.roll?(character, spell, :outgoing, %{spell: shot}, fn -> expected / 100 end)
        refute ProcChance.roll?(character, spell, :outgoing, %{spell: shot}, fn -> (expected + 1) / 100 end)
      end
    end

    test "Hawk talents affect an active aspect immediately and only once", %{character: character} do
      aspect = SpellLoader.load(13_165)
      {character, _} = Aura.apply_spell(character, 1, 60, aspect, 0)
      assert ProcChance.chance(character, aspect, :outgoing, %{}) == 0

      for {talent, amount} <- [{19_552, 1}, {19_556, 5}] do
        {talented, _} = Aura.apply_spell(character, 1, 60, SpellLoader.load(talent), 1_000)
        context = CastContext.from_caster(talented, aspect, 1)
        {recast, _} = Aura.apply_spell(talented, context, aspect, 2_000)
        held = Enum.find(recast.unit.auras, &(&1.spell.id == aspect.id)).spell
        assert held.proc_chance == 0
        assert ProcChance.chance(recast, held, :outgoing, %{}) == amount
        assert ProcChance.chance(talented, held, :outgoing, %{}) == amount
      end
    end

    test "Improved Nature's Grasp adds its chance to the bearer on incoming hits", %{character: character} do
      grasp = SpellLoader.load(16_689)
      assert grasp.proc_chance == 35
      assert ProcChance.chance(character, grasp, :incoming, %{}) == 35
      {talented, _} = Aura.apply_spell(character, 1, 60, SpellLoader.load(17_249), 0)
      context = CastContext.from_caster(talented, grasp, 1)
      {talented, _} = Aura.apply_spell(talented, context, grasp, 0)
      held = Enum.find(talented.unit.auras, &(&1.spell.id == grasp.id)).spell
      assert held.proc_chance == 35
      assert ProcChance.chance(talented, held, :incoming, %{}) == 100
      assert ProcChance.chance(character, held, :incoming, %{}) == 35
    end
  end

  defp character(_context) do
    %{
      character: %Character{
        object: %Object{guid: 1},
        player: %Player{},
        internal: %Internal{},
        unit: %Unit{level: 60, health: 100, max_health: 100, class: 3, auras: [], base_ranged_attack_time: 3_000}
      }
    }
  end
end
