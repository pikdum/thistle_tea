defmodule ThistleTea.Game.Entity.EffectResolver.TriggeredChannelDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EffectResolver.Spells
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.CorpseTarget
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellEffectOverride
  alias ThistleTea.Game.WorldRef

  @moduletag :dbc_db

  setup [:caster]

  setup do
    key = {:aura_interrupt_flags, 20_578}
    old = :ets.lookup(SpellEffectOverride, key)
    :ets.insert(SpellEffectOverride, {key, 2})

    on_exit(fn ->
      :ets.delete(SpellEffectOverride, key)
      :ets.insert(SpellEffectOverride, old)
    end)

    :ok
  end

  describe "resolve/2" do
    test "loads Cannibalize requirements and its real recovery data" do
      root = SpellLoader.load(20_577)
      assert CorpseTarget.required?(%{root | script_name: "spell_cannibalize"})
      assert root.range_yards == 5.0
      assert root.recovery_time_ms == 120_000
      channel = SpellLoader.load(20_578)
      assert Spell.attribute?(channel, :channeled)
      assert channel.duration_ms == 10_000
      assert channel.aura_interrupt_flags == 2

      assert [%Effect{aura: :obs_mod_health, base_points: 6, base_dice: 1, die_sides: 1, amplitude_ms: 2_000}] =
               channel.effects
    end

    test "projects an owner channel and retains its recovery aura", %{caster: caster} do
      effect =
        Effects.trigger_spell(caster.object.guid, 50, caster.object.guid, 20_578,
          extra_attack?: true,
          triggered_by_spell_id: 20_577
        )

      assert [%Effects.StartTriggeredChannel{}] = Spells.resolve(caster, effect)
      entity = caster |> Effects.enqueue(effect) |> EventSink.emit_pending(Context.new(self()))
      assert %Cast{triggered?: true, phase: :channel_tick, spell: %Spell{id: 20_578}} = entity.internal.casting
      assert Aura.has_spell?(entity, 20_578)

      assert %{triggered?: true, triggered_by_aura?: true, extra_attack?: true} =
               entity.internal.casting.trigger_context

      assert_received {:"$gen_cast", {:send_packet, %Message.MsgChannelStart{duration_ms: 10_000}}}
      {healed, _events} = Aura.tick(entity, entity.internal.casting.started_at + 2_000)
      assert healed.unit.health == 170
    end

    test "routes a foreign channel to its original owner", %{caster: caster} do
      guid = caster.object.guid
      effect = Effects.trigger_spell(guid, 50, guid, 20_578)
      mob = %Mob{object: %Object{guid: Guid.runtime(:mob, 1)}}

      assert [%Effects.TriggerSpellRequest{source_guid: ^guid, spell_id: 20_578}] = Spells.resolve(mob, effect)
    end
  end

  defp caster(_context) do
    %{
      caster: %Character{
        object: %Object{guid: System.unique_integer([:positive]) + 83_000_000},
        player: %Player{},
        unit: %Unit{level: 50, health: 100, max_health: 1_000},
        internal: %Internal{world: WorldRef.instance(999, 203)},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }
    }
  end
end
