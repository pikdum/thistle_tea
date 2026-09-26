defmodule ThistleTea.Game.Entity.Logic.LiquidSpellsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.AI.BehaviorRunner
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Player, as: PlayerBT
  alias ThistleTea.Game.Entity.Logic.AI.Tick
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.LiquidSpells
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Terrain.Liquid

  setup [:character]

  describe "spell_id/2" do
    test "requires submersion in a spell-bearing liquid" do
      slime = %Liquid{entry: 21, flags: 4, surface: 10.0, floor: 0.0}
      assert Liquid.spell_id(slime, 9.8) == 28_801

      for height <- [9.92, 10.0, 10.08, 20.0], do: assert(Liquid.spell_id(slime, height) == nil)
      for entry <- [nil, 1, 2, 3, 4], do: assert(Liquid.spell_id(%{slime | entry: entry}, 5.0) == nil)
      assert Liquid.spell_id(nil, 5.0) == nil
    end
  end

  describe "reconcile/3" do
    test "applies all aura effects once without resetting periodic deadlines", %{character: c, context: context} do
      entered = LiquidSpells.reconcile(c, context, 1000)
      assert entered.internal.liquid_spell_id == 28_801
      assert entered.unit.strength == 10
      assert entered.unit.health == 1000
      assert [holder] = entered.unit.auras
      assert holder.negative?
      assert Enum.find(holder.auras, &(&1.type == :periodic_damage)).next_tick_at == 3000
      assert LiquidSpells.reconcile(entered, context, 2000) == entered
      assert Tick.needs_tick?(entered)
    end

    test "restores a removed aura while exposure continues", %{character: c, context: context} do
      entered = LiquidSpells.reconcile(c, context, 1000)
      {removed, _events} = Aura.remove_spells(entered, [context.spell.id], 1500)
      assert removed.unit.strength == 100
      assert LiquidSpells.active?(removed)
      assert Tick.needs_tick?(removed)
      restored = LiquidSpells.reconcile(removed, context, 1600)
      assert restored.unit.strength == 10
      assert [holder] = restored.unit.auras
      assert holder.applied_at == 1600
    end

    test "exit restores stats and removes only the tracked liquid spell", %{character: c, context: context} do
      unrelated = %Spell{id: 999, effects: [%Effect{type: :apply_aura, aura: :water_breathing, base_points: 1}]}
      {c, _events} = Aura.apply_spell(c, 1, 60, unrelated, 0)
      entered = LiquidSpells.reconcile(c, context, 1000)
      exited = LiquidSpells.reconcile(entered, nil, 2000)
      assert exited.unit.strength == 100
      assert exited.internal.liquid_spell_id == nil
      refute Aura.has_spell?(exited, context.spell.id)
      assert Aura.has_spell?(exited, unrelated.id)
      assert LiquidSpells.reconcile(exited, nil, 3000) == exited

      untracked = %{entered | internal: %{entered.internal | liquid_spell_id: nil}}
      assert LiquidSpells.reconcile(untracked, nil, 3000) == untracked
    end

    test "changing liquid replaces its spell through the same lifecycle", %{character: c, context: context} do
      replacement = %{context | spell: %{context.spell | id: 999}}
      entered = LiquidSpells.reconcile(c, context, 1000)
      changed = LiquidSpells.reconcile(entered, replacement, 2000)
      assert changed.internal.liquid_spell_id == 999
      assert changed.unit.strength == 10
      assert [%{spell: %{id: 999}}] = changed.unit.auras
    end

    test "bodies and ghosts clear exposure while resurrection allows it again", %{character: c, context: context} do
      entered = LiquidSpells.reconcile(c, context, 1000)

      for protected <- [
            %{entered | unit: %{entered.unit | health: 0}},
            %{entered | unit: %{entered.unit | health: 1}, player: %{entered.player | flags: 0x10}}
          ] do
        cleared = LiquidSpells.reconcile(protected, context, 2000)
        assert cleared.internal.liquid_spell_id == nil
        assert cleared.unit.strength == 100
        refute Aura.has_spell?(cleared, context.spell.id)
        assert LiquidSpells.reconcile(cleared, context, 3000) == cleared
        {alive, _events} = Death.resurrect(cleared, 1.0, 4000)
        assert Aura.has_spell?(LiquidSpells.reconcile(alive, context, 4000), context.spell.id)
      end
    end
  end

  describe "tick/3" do
    test "leaving liquid removes its aura before an overdue periodic tick", %{character: c, context: context} do
      entered = LiquidSpells.reconcile(c, context, 1000)
      entered = %{entered | internal: %{entered.internal | events: []}}
      {:running, exited} = BehaviorRunner.tick(PlayerBT.tree(), entered, Context.new(10_000))
      assert exited.unit.health == 1000
      assert exited.unit.strength == 100
      refute Aura.has_spell?(exited, context.spell.id)
      refute Enum.any?(exited.internal.events, &is_struct(&1, Effects.SpellDamage))
    end

    test "stationary periodic damage uses shared death cleanup", %{character: c, context: context} do
      c = %{c | unit: %{c.unit | health: 50}}
      entered = LiquidSpells.reconcile(c, context, 1000)
      {:running, dead} = BehaviorRunner.tick(PlayerBT.tree(), entered, Context.new(3000, liquid_spell: context))
      assert dead.unit.health == 0
      refute Aura.has_spell?(dead, context.spell.id)
      {:running, cleared} = BehaviorRunner.tick(PlayerBT.tree(), dead, Context.new(3001, liquid_spell: context))
      assert cleared.internal.liquid_spell_id == nil
      assert cleared.unit.strength == 100
    end
  end

  defp character(_context) do
    spell = %Spell{
      id: 28_801,
      school: :nature,
      attributes: MapSet.new([:negative]),
      duration_ms: -1,
      effects: [
        %Effect{index: 0, type: :apply_aura, aura: :mod_total_stat_percent, base_points: -90, misc_value: -1},
        %Effect{index: 1, type: :apply_aura, aura: :periodic_damage, base_points: 100, amplitude_ms: 2000}
      ]
    }

    character = %Character{
      object: %Object{guid: 1},
      player: %Player{flags: 0},
      unit: %Unit{health: 1000, max_health: 1000, level: 60, base_strength: 100, strength: 100, auras: []},
      internal: %Internal{},
      movement_block: %MovementBlock{movement_flags: 0, position: {0.0, 0.0, -1.0, 0.0}}
    }

    context = %CastContext{
      caster_guid: 1,
      target_guid: 1,
      caster_level: 60,
      caster_type: :player,
      target_role: :caster,
      triggered?: true,
      spell: spell
    }

    %{character: character, context: context}
  end
end
