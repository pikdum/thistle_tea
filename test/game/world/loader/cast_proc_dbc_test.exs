defmodule ThistleTea.Game.World.Loader.CastProcDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Proc
  alias ThistleTea.Game.Spell.ProcOrigin
  alias ThistleTea.Game.Spell.ProcRule
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "real channel exceptions distinguish ordinary proc auras from CAN_PROC_FROM_PROCS" do
      absorption = %{SpellLoader.load(29_447) | proc_type_mask: 0x10000, proc_rule: nil}
      assert Spell.attribute?(absorption, :can_proc_from_procs)
      ordinary = %{absorption | attributes: MapSet.new()}
      context = %CastContext{triggered?: true, triggered_by_aura?: true}

      for {id, ordinary_allowed?} <- [{7_268, true}, {5_857, false}] do
        spell = SpellLoader.load(id)
        origin = ProcOrigin.classify(spell, context)
        assert origin == :aura_or_item
        hit = %{outcome: :normal, proc_origin: origin}
        assert Proc.eligible?(absorption, spell, :deal_harmful_spell, hit)
        assert Proc.eligible?(ordinary, spell, :deal_harmful_spell, hit) == ordinary_allowed?
      end
    end

    test "Elemental Focus accepts the Shaman damage family at cast completion" do
      rule = %ProcRule{proc_ex: 0x80000, school_mask: 28, spell_family: 11, proc_flags: 0x10000}
      focus = %{SpellLoader.load(16_164) | proc_rule: rule}
      assert focus.proc_chance == 10
      assert Enum.any?(focus.effects, &(&1.trigger_spell_id == 16_246))

      for id <- [403, 8050, 8056] do
        spell = SpellLoader.load(id)
        assert Proc.eligible?(focus, spell, Proc.cast_type(spell), :cast_end)
        refute Proc.eligible?(focus, spell, Proc.cast_type(spell), :normal)
      end

      for id <- [116, 331] do
        spell = SpellLoader.load(id)
        refute Proc.eligible?(focus, spell, Proc.cast_type(spell), :cast_end)
      end
    end

    test "Blue Dragon accepts helpful and harmful casts but respects caster suppression" do
      dragon = %{SpellLoader.load(23_688) | proc_rule: %ProcRule{proc_ex: 0x80000}}
      assert dragon.proc_chance == 2
      assert Enum.any?(dragon.effects, &(&1.trigger_spell_id == 23_684))

      for id <- [403, 331] do
        spell = SpellLoader.load(id)
        assert Proc.eligible?(dragon, spell, Proc.cast_type(spell), :cast_end)
        refute Proc.eligible?(dragon, spell, Proc.cast_type(spell), :normal)
      end

      intellect = SpellLoader.load(1459)
      assert Proc.cast_type(intellect) == :deal_helpful_ability
      refute Proc.eligible?(dragon, intellect, Proc.cast_type(intellect), :cast_end)

      for id <- [1130, 2855] do
        spell = SpellLoader.load(id)
        assert Spell.attribute?(spell, :suppress_caster_procs)
        refute Proc.eligible?(dragon, spell, Proc.cast_type(spell), :cast_end)
      end
    end
  end
end
