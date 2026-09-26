defmodule ThistleTea.Game.World.Loader.TargetTriggerDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.TargetTrigger
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellEffectOverride

  @moduletag :dbc_db

  setup [:caster]

  describe "load/1" do
    test "Relentless Strikes has a 20 percent chance per finisher point", %{caster: caster} do
      talent = SpellLoader.load(14_179)
      {caster, _} = Aura.apply_spell(caster, 1, 60, talent, 0)
      assert [%{auras: [%{amount: 0}]}] = caster.unit.auras

      for id <- [2098, 8647, 5171, 1943, 408] do
        context = CastContext.from_caster(caster, SpellLoader.load(id), 2)
        assert [%Effects.TriggerSpell{spell_id: 14_181}] = TargetTrigger.events(context, 1)
        assert TargetTrigger.events(context, 2) == []
        assert TargetTrigger.events(%{context | combo_points: 0}, 1) == []
        {_, events} = SpellEffect.receive(caster, %{context | target_role: :caster}, SpellLoader.load(id), 1_000)
        assert length(Enum.filter(events, &is_struct(&1, Effects.TriggerSpell))) == 1
      end

      context = CastContext.from_caster(caster, SpellLoader.load(1752), 2)
      assert context.target_triggers == []
    end

    test "Frostbite applies to Chilled rather than every frost spell", %{caster: caster} do
      for {id, chance} <- [{11_071, 5}, {12_496, 10}, {12_497, 15}] do
        {buffed, _} = Aura.apply_spell(caster, 1, 60, SpellLoader.load(id), 0)
        context = CastContext.from_caster(buffed, SpellLoader.load(12_486), 2)
        assert [%TargetTrigger{chance: ^chance, spell_id: 12_494}] = context.target_triggers
        assert CastContext.from_caster(buffed, SpellLoader.load(10), 2).target_triggers == []
        assert CastContext.from_caster(buffed, SpellLoader.load(12_494), 2).target_triggers == []
      end
    end

    test "Revealed Flaw loads the VMangos class-mask fixture and scales with points", %{caster: caster} do
      key = {:class_masks, 28_814}
      previous = :ets.lookup(SpellEffectOverride, key)
      :ets.insert(SpellEffectOverride, {key, {0x20000, 0, 0}})

      on_exit(fn ->
        :ets.delete(SpellEffectOverride, key)
        :ets.insert(SpellEffectOverride, previous)
      end)

      talent = SpellLoader.load(28_814)
      assert hd(talent.effects).class_mask == 0x20000
      {caster, _} = Aura.apply_spell(caster, 1, 60, talent, 0)
      context = CastContext.from_caster(caster, SpellLoader.load(2098), 2)
      assert [%TargetTrigger{chance: 0, points_per_combo: 5.0, spell_id: 28_815}] = context.target_triggers
      assert [%Effects.TriggerSpell{}] = TargetTrigger.events(context, 1, fn -> 0.25 end)
      assert TargetTrigger.events(context, 1, fn -> 0.251 end) == []
      assert TargetTrigger.events(context, 2, fn -> 0.01 end) == []
      assert CastContext.from_caster(caster, SpellLoader.load(1943), 2).target_triggers == []
    end
  end

  defp caster(_context) do
    %{
      caster: %Character{
        object: %Object{guid: 1},
        unit: %Unit{level: 60, health: 100, max_health: 100, auras: []},
        player: %Player{combo_points: 5},
        internal: %Internal{}
      }
    }
  end
end
