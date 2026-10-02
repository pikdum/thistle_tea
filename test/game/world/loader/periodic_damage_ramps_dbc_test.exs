defmodule ThistleTea.Game.World.Loader.PeriodicDamageRampsDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.EventSink
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Test.Unique

  @moduletag :dbc_db

  setup [:target]

  describe "load/1" do
    test "Renew and Corruption restart their interval when recast", %{target: target} do
      for id <- [139, 172] do
        spell = SpellLoader.load(id)
        assert hd(spell.effects).amplitude_ms == 3_000
        {target, _events} = Aura.apply_spell(target, 2, 60, spell, 0)
        {target, _events} = Aura.tick(target, 3_000)
        {target, _events} = Aura.apply_spell(target, 2, 60, spell, 3_500)
        assert [%{auras: [%{tick_count: 0, next_tick_at: 6_500}]}] = target.unit.auras
        assert {^target, []} = Aura.tick(target, 6_000)
        {target, _events} = Aura.tick(target, 6_500)
        assert [%{auras: [%{tick_count: 1, next_tick_at: 9_500}]}] = target.unit.auras
      end
    end

    test "every player rank ramps from its own unmodified base", %{target: target} do
      ranks = [
        {4, 2, [980, 1014, 6217, 11_711, 11_712, 11_713]},
        {2, 3, [10_797, 19_296, 19_299, 19_302, 19_303, 19_304, 19_305]}
      ]

      for {stage_length, divisor, ids} <- ranks, id <- ids do
        spell = SpellLoader.load(id)
        effect = Enum.find(spell.effects, &(&1.index == 0))
        assert effect.aura == :periodic_damage
        assert div(spell.duration_ms, effect.amplitude_ms) == stage_length * 3
        assert Spell.attribute?(spell, :channeled) == (divisor == 3)
        base = effect.base_points + effect.base_dice
        context = %CastContext{caster_guid: 2, caster_level: 60, spell_damage_bonus: %{arcane: 100, shadow: 100}}
        {target, _events} = Aura.apply_spell(target, context, spell, 0)
        snapshot = hd(hd(target.unit.auras).auras).amount

        final =
          Enum.reduce(1..(stage_length * 3), target, fn tick, current ->
            {next, events} = Aura.tick(current, tick * effect.amplitude_ms)
            assert [%Effects.SpellDamage{damage: damage, resisted: 0, absorbed: 0}] = events
            expected = snapshot + (div(tick - 1, stage_length) - 1) * base / divisor
            assert damage in [floor(expected), ceil(expected)]
            assert next.unit.health == current.unit.health - damage
            next
          end)

        assert final.unit.auras == []
        assert Aura.next_event_at(final) == nil
      end
    end

    test "Starshards reports each actual health change to both native packet recipients", %{target: target} do
      caster_guid = target.object.guid + 1

      for guid <- [target.object.guid, caster_guid] do
        {:ok, _} = Entity.register(guid)
        SpatialHash.insert(:players, guid, target.internal.world, 0.0, 0.0, 0.0)
      end

      on_exit(fn ->
        for guid <- [target.object.guid, caster_guid] do
          Entity.unregister(guid)
          SpatialHash.remove(:players, guid)
        end
      end)

      spell = SpellLoader.load(19_305)
      {target, _events} = Aura.apply_spell(target, caster_guid, 60, spell, 0)

      Enum.reduce(1..6, target, fn tick, current ->
        {next, [damage]} = Aura.tick(current, tick * 1_000)
        EventSink.emit(next, damage)
        health_loss = current.unit.health - next.unit.health

        assert_receive {:"$gen_cast",
                        {:send_packet,
                         %Message.SmsgSpellNonMeleeDamageLog{
                           spell_id: 19_305,
                           damage: ^health_loss,
                           periodic?: true
                         }, _opts}}

        assert_receive {:"$gen_cast",
                        {:send_packet,
                         %Message.SmsgSpellNonMeleeDamageLog{
                           spell_id: 19_305,
                           damage: ^health_loss,
                           periodic?: true
                         }}}

        next
      end)
    end
  end

  defp target(_context) do
    guid = Unique.integer()

    %{
      target: %Character{
        object: %Object{guid: guid},
        unit: %Unit{level: 60, health: 100_000, max_health: 100_000, auras: []},
        internal: %Internal{world: WorldRef.instance(0, guid)},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }
    }
  end
end
