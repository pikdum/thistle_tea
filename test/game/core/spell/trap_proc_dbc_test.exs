defmodule ThistleTea.Game.Core.Spell.TrapProcDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity, as: EntityCore
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.PersistentArea
  alias ThistleTea.Game.Core.Spell.PersistentArea.Check
  alias ThistleTea.Game.Core.Spell.Proc
  alias ThistleTea.Game.Core.Spell.ProcRule
  alias ThistleTea.Game.Core.Spell.SpellEffect
  alias ThistleTea.Game.Core.Spell.SpellFeedback
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.EventSink
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellChain
  alias ThistleTea.Game.World.Loader.SpellProcEvent
  alias ThistleTea.Game.World.Loader.SpellScriptName
  alias ThistleTea.Game.World.Loader.Talent

  @moduletag :dbc_db
  @ranks [19_184, 19_387, 19_388, 19_389, 19_390]

  setup [:catalog, :characters]

  describe "receive/4" do
    test "all ranks retain their real chances and eligible trap families" do
      for {id, chance} <- Enum.zip(@ranks, [5, 10, 15, 20, 25]) do
        talent = SpellLoader.load(id)
        assert talent.proc_chance == chance
        assert Proc.eligible?(talent, SpellLoader.load(13_797), :deal_harmful_spell, :normal)
        assert Proc.eligible?(talent, SpellLoader.load(13_812), :deal_harmful_spell, :normal)
        assert Proc.eligible?(talent, SpellLoader.load(13_810), :trap_activation, :normal)
        refute Proc.eligible?(talent, SpellLoader.load(3355), :deal_harmful_spell, :normal)
      end
    end

    test "non-damaging trap hits reach the caster and root through its current talent", ctx do
      {:ok, _} = Entity.register(ctx.caster.object.guid)
      spell = SpellLoader.load(13_797)
      {target, events} = SpellEffect.receive(ctx.target, CastContext.from_caster(ctx.caster, spell, 2), spell, 0)
      assert [%Effects.SpellProc{} = event] = Enum.filter(events, &is_struct(&1, Effects.SpellProc))
      EventSink.emit(target, event)
      assert_receive {:"$gen_cast", {:spell_outcome, payload}}
      assert payload.victim_guid == 2
      assert payload.victim_alive?
      caster = SpellFeedback.receive(ctx.caster, payload, spell, 0)
      assert [%Effects.TriggerSpell{spell_id: 19_185, source_guid: 1, target_guid: 2}] = triggers(caster)

      root = SpellLoader.load(19_185)
      {rooted, _} = SpellEffect.receive(target, CastContext.from_caster(caster, root, 2), root, 0)
      assert Aura.has_aura?(rooted, :mod_root)
      {expired, _} = Aura.tick(rooted, 5_000)
      refute Aura.has_aura?(expired, :mod_root)

      caster = %{ctx.caster | unit: %{ctx.caster.unit | auras: []}}
      assert triggers(SpellFeedback.receive(caster, payload, spell, 0)) == []
    end

    test "Explosive Trap delivers one proc check alongside its immediate damage", ctx do
      spell = SpellLoader.load(13_812)
      context = CastContext.from_caster(ctx.caster, spell, 2)
      {target, events} = SpellEffect.receive(ctx.target, context, spell, 0)
      assert target.unit.health < ctx.target.unit.health
      assert [%Effects.SpellDamage{} = damage] = Enum.filter(events, &is_struct(&1, Effects.SpellDamage))
      refute Enum.any?(events, &is_struct(&1, Effects.SpellProc))
      {:ok, _} = Entity.register(1)
      EventSink.emit(target, damage)
      assert_receive {:"$gen_cast", {:spell_outcome, payload}}
      assert length(triggers(SpellFeedback.receive(ctx.caster, payload, spell, 0))) == 1
    end

    test "resisted trap applications cannot report successful activation", ctx do
      spell = SpellLoader.load(13_797)
      context = %{CastContext.from_caster(ctx.caster, spell, 2) | hit_outcome: :resist}
      {target, events} = SpellEffect.receive(ctx.target, context, spell, 0)
      refute Aura.has_spell?(target, spell.id)
      refute Enum.any?(events, &is_struct(&1, Effects.SpellProc))
      assert Enum.any?(events, &is_struct(&1, Effects.SpellLogMiss))
    end
  end

  describe "tick/3" do
    test "Frost Trap checks every two seconds without rerolling on area refreshes", ctx do
      {target, context, spell} = frost_area(ctx)
      {target, events} = Aura.tick(target, 1_999)
      assert proc_events(events) == []
      {target, events} = Aura.tick(target, 2_000)
      assert [%Effects.SpellProc{proc_type: :trap_activation}] = proc_events(events)
      {target, events} = SpellEffect.receive(target, context, spell, 2_250)
      assert proc_events(events) == []
      {target, events} = Aura.tick(target, 3_999)
      assert proc_events(events) == []
      {_target, events} = Aura.tick(target, 4_000)
      assert length(proc_events(events)) == 1
    end

    test "leaving the area, removing the source, expiry and death stop trap checks", ctx do
      {target, _context, _spell} = frost_area(ctx)
      holder = hd(target.unit.auras)
      context = %{holder.cast_context | area_checks: %{100 => %Check{available?: false}}}
      key = {holder.spell.id, holder.caster_guid, holder.item_source}
      {left, events} = Aura.tick(target, 2_000, %{key => context})
      assert proc_events(events) == []
      refute Aura.has_spell?(left, 13_810)

      {removed, _} = Aura.remove_area_aura(target, 100, 1_000)
      {_, events} = Aura.tick(removed, 2_000)
      assert proc_events(events) == []
      {expired, _} = Aura.tick(target, 30_000)
      {_, events} = Aura.tick(expired, 32_000)
      assert proc_events(events) == []
      dead = EntityCore.take_damage(target, 20_000, 1_000)
      {_, events} = Aura.tick(dead, 2_000)
      assert proc_events(events) == []
    end
  end

  defp frost_area(ctx) do
    spell = SpellLoader.load(13_810)
    effect = Enum.find(spell.effects, &(&1.aura == :periodic_trigger_spell))
    assert effect.amplitude_ms == 2_000
    spell = %{spell | effects: [%{effect | type: :apply_aura, semantic: nil}]}

    area = %PersistentArea{
      guid: 100,
      position: {WorldRef.open(0), 0.0, 0.0, 0.0},
      radius: 10.0,
      started_at: 0,
      expires_at: 30_000
    }

    context = %{CastContext.from_caster(ctx.caster, spell, 2) | persistent_area: area}
    {target, events} = SpellEffect.receive(ctx.target, context, spell, 0)
    assert proc_events(events) == []
    {target, context, spell}
  end

  defp proc_events(events), do: Enum.filter(events, &is_struct(&1, Effects.SpellProc))
  defp triggers(entity), do: Enum.filter(entity.internal.events, &is_struct(&1, Effects.TriggerSpell))

  defp catalog(_context) do
    entries =
      [
        {SpellProcEvent, 19_184, %ProcRule{spell_family: 9, family_mask_0: 0x14}},
        {SpellScriptName, 13_810, "spell_hunter_frost_trap_aura"}
      ] ++
        Enum.map(@ranks ++ [19_185, 13_797, 13_812, 13_810, 3355], &{SpellChain, {:chain, &1}, nil})

    for {table, key, value} <- entries do
      previous = :ets.lookup(table, key)
      :ets.insert(table, {key, value})

      on_exit(fn ->
        :ets.delete(table, key)
        :ets.insert(table, previous)
      end)
    end

    Talent.load_all()
  end

  defp characters(_context) do
    caster = %Character{
      object: %Object{guid: 1},
      player: %Player{},
      internal: %Internal{},
      unit: %Unit{level: 60, health: 10_000, max_health: 10_000, auras: []},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    target = %{caster | object: %Object{guid: 2}}
    talent = %{SpellLoader.load(19_390) | proc_chance: 100}
    {caster, _} = Aura.apply_spell(caster, 1, 60, talent, 0)
    %{caster: caster, target: target}
  end
end
