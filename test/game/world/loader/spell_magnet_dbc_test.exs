defmodule ThistleTea.Game.World.Loader.SpellMagnetDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellMagnet
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "Grounding's passive pulses immediately and then every ten seconds" do
      spell = SpellLoader.load(8179)
      mob = %Mob{object: %Object{guid: 1}, unit: %Unit{health: 100, auras: []}}
      {mob, _} = Aura.apply_spell(mob, 1, 50, spell, 100)
      assert hd(hd(mob.unit.auras).auras).next_tick_at == 100
      {mob, events} = Aura.tick(mob, 100)
      assert Enum.any?(events, &match?(%Effects.TriggerSpell{spell_id: 8178}, &1))
      assert hd(hd(mob.unit.auras).auras).next_tick_at == 10_100
    end

    test "Grounding Totem supplies a shared single-charge party aura" do
      spell = SpellLoader.load(8178)
      assert spell.proc_charges == 1
      assert [%{type: :apply_area_aura, aura: :spell_magnet, radius_yards: 20.0}] = spell.effects
    end

    test "recognizes harmful spells and the redirection bypass on Cause Insanity" do
      for id <- [133, 116, 172], do: assert(SpellMagnet.eligible?(SpellLoader.load(id)))
      for id <- [8004, 24_327, 26_180], do: refute(SpellMagnet.eligible?(SpellLoader.load(id)))
    end
  end
end
