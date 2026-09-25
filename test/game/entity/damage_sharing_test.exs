defmodule ThistleTea.Game.Entity.DamageSharingTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.DamageSharing
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.SpellReception
  alias ThistleTea.Game.Network.Message.SmsgSpellNonMeleeDamageLog
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  setup [:entities]

  describe "targets/1" do
    test "refreshes availability for death, world changes and removal", ctx do
      assert DamageSharing.targets(ctx.target) == MapSet.new([ctx.caster])
      Metadata.update(ctx.caster, %{alive?: false})
      assert DamageSharing.targets(ctx.target) == MapSet.new()
      Metadata.update(ctx.caster, %{alive?: true})
      SpatialHash.update(:players, ctx.caster, WorldRef.instance(0, 9), 0.0, 0.0, 0.0)
      assert DamageSharing.targets(ctx.target) == MapSet.new()
      SpatialHash.update(:players, ctx.caster, ctx.target.internal.world, 0.0, 0.0, 0.0)
      assert DamageSharing.targets(ctx.target) == MapSet.new([ctx.caster])
      SpatialHash.remove(:players, ctx.caster)
      assert DamageSharing.targets(ctx.target) == MapSet.new()
    end
  end

  describe "SpellReception.receive/4" do
    test "refreshes sharing at impact instead of using the attacker's snapshot", ctx do
      spell = %Spell{id: 9, school: :physical, effects: [%Effect{type: :school_damage, base_points: 100}]}
      context = %CastContext{caster_guid: ctx.attacker, caster_level: 60}
      {target, _events} = SpellReception.receive(ctx.target, context, spell, 1_000)
      assert target.unit.health == 930
      assert [%Effects.SharedDamage{damage: 30}] = transfers(target)

      Metadata.update(ctx.caster, %{alive?: false})
      context = %{context | damage_sharing_targets: MapSet.new([ctx.caster])}
      {target, _events} = SpellReception.receive(ctx.target, context, spell, 2_000)
      assert target.unit.health == 900
      assert transfers(target) == []
    end
  end

  describe "SpellReception.aura_contexts/2" do
    test "refreshes each periodic tick and retains exhausted shield removal", ctx do
      spell = %Spell{
        id: 10,
        school: :physical,
        duration_ms: 6_000,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :periodic_damage, base_points: 100, amplitude_ms: 1_000}]
      }

      {target, _} = AuraLogic.apply_spell(ctx.target, ctx.attacker, 60, spell, 0)

      shield = %Holder{
        spell: %Spell{id: 11},
        caster_guid: target.object.guid,
        auras: [%Aura{type: :school_absorb, amount: 20, misc_value: 127}]
      }

      target = %{target | unit: %{target.unit | auras: target.unit.auras ++ [shield]}}
      {target, _} = AuraLogic.tick(target, 1_000, SpellReception.aura_contexts(target, 1_000))
      assert target.unit.health == 944
      assert [%Effects.SharedDamage{damage: 24}] = transfers(target)
      refute Enum.any?(target.unit.auras, &(&1.spell.id == 11))

      Metadata.update(ctx.caster, %{alive?: false})
      target = %{target | internal: %{target.internal | events: []}}
      {target, _} = AuraLogic.tick(target, 2_000, SpellReception.aura_contexts(target, 2_000))
      assert target.unit.health == 844
      assert transfers(target) == []
    end
  end

  describe "receive/3" do
    test "rejects a transfer that arrives after a world change", ctx do
      effect = transfer(ctx)
      target = %{ctx.target | internal: %{ctx.target.internal | world: WorldRef.open(1)}}
      assert DamageSharing.receive(target, effect, 1_000) == target
    end
  end

  describe "EventSink.emit/3" do
    test "delivers through the entity owner and requires explicit context for local delivery", ctx do
      effect = transfer(ctx)
      EventSink.emit(ctx.target, effect)
      refute_received {:"$gen_cast", {:receive_shared_damage, _}}
      EventSink.emit(ctx.target, effect, Context.new(self()))
      assert_received {:"$gen_cast", {:receive_shared_damage, ^effect}}
      Entity.register(ctx.target.object.guid)
      on_exit(fn -> Entity.unregister(ctx.target.object.guid) end)
      remote = %{ctx.target | object: %Object{guid: ctx.attacker}}
      EventSink.emit(remote, effect)
      assert_received {:"$gen_cast", {:receive_shared_damage, ^effect}}
    end

    test "projects the actual sharing spell and school without offensive proc feedback", ctx do
      target = ctx.target
      Entity.register(target.object.guid)
      SpatialHash.update(:players, target.object.guid, target.internal.world, 0.0, 0.0, 0.0)

      on_exit(fn ->
        Entity.unregister(target.object.guid)
        SpatialHash.remove(:players, target.object.guid)
      end)

      target = target |> DamageSharing.receive(transfer(ctx), 1_000) |> EventSink.emit_pending()
      assert target.unit.health == 970

      assert_receive {:"$gen_cast",
                      {:send_packet,
                       %SmsgSpellNonMeleeDamageLog{
                         attacker: attacker,
                         spell_id: 25_228,
                         school: 0,
                         damage: 30,
                         absorbed: 0,
                         hit_info: 0
                       }}}

      assert attacker == ctx.attacker
      refute_received {:"$gen_cast", {:spell_outcome, _}}
    end
  end

  defp transfer(ctx) do
    %Effects.SharedDamage{
      target_guid: ctx.target.object.guid,
      source_guid: ctx.attacker,
      world: ctx.target.internal.world,
      spell: %Spell{id: 25_228},
      school: :physical,
      damage: 30,
      kind: :split_damage_percent
    }
  end

  defp transfers(entity), do: Enum.filter(entity.internal.events, &is_struct(&1, Effects.SharedDamage))

  defp entities(_ctx) do
    [guid, caster, attacker] = guids = for _ <- 1..3, do: System.unique_integer([:positive])

    holder = %Holder{
      spell: %Spell{id: 25_228},
      caster_guid: caster,
      slot: 0,
      auras: [%Aura{type: :split_damage_percent, amount: 30, misc_value: 127}]
    }

    target = %Character{
      object: %Object{guid: guid},
      unit: %Unit{level: 60, health: 1_000, max_health: 1_000, auras: [holder]},
      player: %Player{},
      internal: %Internal{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    Metadata.put(caster, %{alive?: true})
    SpatialHash.update(:players, caster, target.internal.world, 0.0, 0.0, 0.0)

    on_exit(fn ->
      SpatialHash.remove(:players, caster)
      Enum.each(guids, &Metadata.delete/1)
    end)

    %{target: target, caster: caster, attacker: attacker}
  end
end
