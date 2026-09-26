defmodule ThistleTea.Game.Entity.Logic.PyroclasmDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EffectResolver.Spells
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Logic.SpellFeedback
  alias ThistleTea.Game.Entity.Server.Mob, as: MobServer
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.PersistentArea
  alias ThistleTea.Game.Spell.PersistentArea.Check
  alias ThistleTea.Game.Spell.ProcRule
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellChain
  alias ThistleTea.Game.World.Loader.SpellProcEvent
  alias ThistleTea.Game.World.Loader.Talent
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.WorldRef

  @moduletag :dbc_db

  setup [:catalog, :characters]

  describe "receive/4" do
    test "creature owners retain unlearned damage spells in proc feedback", context do
      guid = Guid.from_low_guid(:mob, 1, System.unique_integer([:positive]))

      mob = %Mob{
        object: %Object{guid: guid},
        unit: context.caster.unit,
        internal: %Internal{world: WorldRef.open(0), spellbook: %{}},
        movement_block: context.caster.movement_block
      }

      {mob, _} = Aura.apply_spell(mob, guid, 60, SpellLoader.load(18_073), 0)
      {:ok, _} = Entity.register(context.target.object.guid)
      spell = SpellLoader.load(5857)
      refute Map.has_key?(mob.internal.spellbook, spell.id)

      feedback = %{
        victim_guid: context.target.object.guid,
        victim_alive?: true,
        damage: 100,
        proc_type: :deal_harmful_spell,
        outcome: :normal,
        spell_id: spell.id,
        spell: spell
      }

      :rand.seed(:exsss, {34, 2, 3})

      assert {:noreply, updated, {:continue, :maybe_broadcast}} =
               MobServer.handle_cast({:spell_outcome, feedback}, mob)

      assert_receive {:"$gen_cast", {:receive_spell, cast_context, %{id: 18_093}}}
      assert cast_context.caster_guid == guid
      assert updated.internal.events == []
      Process.cancel_timer(updated.internal.ai_tick_ref)
    end

    test "both ranks proc from Soul Fire, Hellfire, and Rain of Fire through owner feedback", context do
      for talent_id <- [18_096, 18_073], damage_id <- [6353, 5857, 5740] do
        {caster, _} = Aura.apply_spell(context.caster, 1, 60, SpellLoader.load(talent_id), 0)
        spell = SpellLoader.load(damage_id)
        {target, damage} = damage(context.target, caster, spell)
        assert damage.damage > 0
        assert damage.proc_type == if(damage_id == 5740, do: :deal_harmful_periodic, else: :deal_harmful_spell)
        EventSink.emit(target, damage)
        assert_receive {:"$gen_cast", {:spell_outcome, feedback}}
        assert feedback.victim_alive?
        assert feedback.spell == damage.spell
        refute Map.has_key?(caster.internal.spellbook, damage_id)
        :rand.seed(:exsss, {34, 2, 3})

        assert {:noreply, %{character: caster}, {:continue, :maybe_broadcast_update}} =
                 PlayerServer.handle_cast({:spell_outcome, feedback}, %{character: caster})

        {caster, events} = Effects.drain(caster)
        assert [%Effects.TriggerSpell{spell_id: 18_093} = proc] = events
        assert proc.triggering_spell_id == talent_id
        assert proc.target_guid == target.object.guid
        assert Enum.map(caster.unit.auras, & &1.spell.id) == [talent_id]
        assert hd(caster.unit.auras).charges == nil

        delivery = caster |> Spells.resolve(proc) |> Enum.find(&is_struct(&1, Effects.DeliverSpell))
        assert delivery.target_guid == target.object.guid
        {target, events} = SpellEffect.receive(target, delivery.cast_context, delivery.spell, 2_000)
        stun = Enum.find(target.unit.auras, &(&1.spell.id == 18_093))
        assert stun.caster_guid == caster.object.guid
        assert stun.expires_at == 5_000
        assert stun.diminishing_group == :triggered_stun
        assert Aura.has_aura?(target, :mod_stun)
        assert Enum.any?(events, &match?(%Effects.AuraDuration{duration_ms: 3_000}, &1))
        {expired, _} = Aura.expire_due(target, 5_000)
        refute Aura.has_aura?(expired, :mod_stun)
        assert expired.internal.diminishing_returns.triggered_stun.reset_at == 20_000
        dead = Core.take_damage(target, target.unit.health, 3_000)
        refute Aura.has_aura?(dead, :mod_stun)
        assert dead.internal.diminishing_returns == %{}
      end
    end

    test "failed rolls and ineligible outcomes retain the talent without firing the placeholder", context do
      {caster, _} = Aura.apply_spell(context.caster, 1, 60, SpellLoader.load(18_073), 0)

      feedback = %{
        victim_guid: context.target.object.guid,
        victim_alive?: true,
        damage: 100,
        proc_type: :deal_harmful_spell,
        outcome: :normal
      }

      soul_fire = SpellLoader.load(6353)
      :rand.seed(:exsss, {1, 2, 3})
      assert SpellFeedback.receive(caster, feedback, soul_fire, 0) == caster

      for {payload, spell} <- [
            {%{feedback | victim_guid: caster.object.guid, proc_type: :deal_harmful_periodic}, SpellLoader.load(1949)},
            {%{feedback | victim_alive?: false}, soul_fire},
            {%{feedback | outcome: :resist}, soul_fire},
            {%{feedback | outcome: :immune}, soul_fire},
            {%{feedback | outcome: :cast_end}, soul_fire},
            {feedback, SpellLoader.load(686)},
            {%{feedback | proc_type: :deal_harmful_periodic}, SpellLoader.load(172)}
          ] do
        :rand.seed(:exsss, {34, 2, 3})
        assert SpellFeedback.receive(caster, payload, spell, 0) == caster
      end
    end
  end

  describe "load/1" do
    test "rank two inherits the proc restriction and all spell ranks retain their channel chances" do
      for talent_id <- [18_096, 18_073] do
        talent = SpellLoader.load(talent_id)
        assert talent.first_in_chain == 18_096
        assert talent.proc_chance == 100
        assert %ProcRule{family_mask_0: 0x60, family_mask_1: 0x80, proc_flags: 0x50400} = talent.proc_rule
        assert Enum.any?(talent.effects, &(&1.aura == :proc_trigger_spell and &1.trigger_spell_id == 18_350))
      end

      for id <- [6353, 17_924] do
        assert %{spell_family: 5, spell_icon: 184, spell_visual: 2253} = SpellLoader.load(id)
      end

      for id <- [1949, 11_683, 11_684] do
        spell = SpellLoader.load(id)
        assert spell.duration_ms == 15_000
        assert Enum.find(spell.effects, &(&1.aura == :periodic_trigger_spell)).amplitude_ms == 1_000
      end

      for id <- [5740, 6219, 11_677, 11_678] do
        spell = SpellLoader.load(id)
        assert spell.duration_ms == 8_000
        assert hd(spell.effects).amplitude_ms == 2_000
      end
    end
  end

  defp damage(target, caster, %{id: 5740} = spell) do
    [effect] = spell.effects
    delivered = %{spell | effects: [%{effect | type: :apply_aura, semantic: nil}]}

    area = %PersistentArea{
      guid: 99,
      position: {WorldRef.open(0), 0.0, 0.0, 0.0},
      radius: 8.0,
      started_at: 0,
      expires_at: 8_000
    }

    context = %{
      CastContext.from_caster(caster, delivered, target.object.guid)
      | persistent_area: area,
        area_checks: %{99 => %Check{hit_roll: 0}}
    }

    {target, _} = Aura.apply_spell(target, context, delivered, 0)
    {target, events} = Aura.tick(target, 2_000, %{{spell.id, caster.object.guid, nil} => context})
    {target, Enum.find(events, &is_struct(&1, Effects.SpellDamage))}
  end

  defp damage(target, caster, spell) do
    context = CastContext.from_caster(caster, spell, target.object.guid)
    {target, events} = SpellEffect.receive(target, context, spell, 0)
    {target, Enum.find(events, &is_struct(&1, Effects.SpellDamage))}
  end

  defp catalog(_context) do
    rule = %ProcRule{family_mask_0: 0x60, family_mask_1: 0x80, proc_flags: 0x50400}

    for {table, key, value} <- [
          {SpellProcEvent, 18_096, rule},
          {SpellChain, {:chain, 18_096}, nil},
          {SpellChain, {:chain, 18_073}, nil}
        ] do
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
      unit: %Unit{level: 60, health: 5_000, max_health: 5_000, auras: []},
      player: %Player{},
      internal: %Internal{spellbook: %{1949 => SpellLoader.load(1949)}},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    target_guid = System.unique_integer([:positive]) + 50_000_000
    target = %{caster | object: %Object{guid: target_guid}}
    Metadata.put(target_guid, %{alive?: true, level: 60})
    on_exit(fn -> Metadata.delete(target_guid) end)
    {:ok, _} = Entity.register(caster.object.guid)
    %{caster: caster, target: target}
  end
end
