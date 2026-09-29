defmodule ThistleTea.Game.World.Entity.EffectResolver.ItemSpellDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Effects.RandomChoice
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.SpellEffect
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Entity.EffectResolver.Spells
  alias ThistleTea.Game.World.Entity.EventSink
  alias ThistleTea.Game.World.Entity.EventSink.Context
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash

  @moduletag :dbc_db
  @spells [8342, 22_999, 8338, 23_055, 14_537, 11_921, 13_322, 21_179, 13_323, 25_189, 14_642]

  setup [:entities]

  describe "resolve/2" do
    test "cable failures damage and stun only the caster without creating an offer", %{caster: caster} do
      dead = %{
        caster
        | object: %Object{guid: Guid.from_low_guid(:player, System.unique_integer([:positive]))},
          unit: %{caster.unit | health: 0}
      }

      for {id, damage, failure_id} <- [{8342, 50, 8338}, {22_999, 100, 23_055}] do
        [failure] = outcomes(caster, dead, id, 100)
        assert [%Effects.TriggerSpellRequest{source_guid: source}] = Spells.resolve(dead, failure)
        assert source == caster.object.guid
        {injured, events} = deliver(caster, caster, failure)
        assert injured.unit.health == caster.unit.health - damage
        assert Aura.has_spell?(injured, failure_id)
        assert Aura.has_aura?(injured, :mod_stun)
        assert Enum.any?(events, &match?(%Effects.SpellDamage{damage: ^damage}, &1))
        {recovered, _} = Aura.tick(injured, 3_001)
        refute Aura.has_aura?(recovered, :mod_stun)
        assert dead.internal.pending_resurrect == nil

        failed = EventSink.emit(dead, failure, Context.new(self()))
        assert failed == dead
        refute_received {:"$gen_cast", {:send_packet, %Message.SmsgResurrectRequest{}}}

        offered = EventSink.emit(dead, outcomes(caster, dead, id, 1), Context.new(self()))
        assert offered.internal.pending_resurrect.health == 150
        assert offered.internal.pending_resurrect.mana == 120
        assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgResurrectRequest{}}}
      end
    end

    test "bag damage uses real child spells and chain lightning resolves all three targets", context do
      for roll <- [1, 26] do
        [trigger] = outcomes(context.caster, context.target, 14_537, roll)
        {injured, events} = deliver(context.caster, context.target, trigger)
        assert injured.unit.health < context.target.unit.health
        assert Enum.any?(events, &is_struct(&1, Effects.SpellDamage))
        if roll == 26, do: assert(Aura.has_spell?(injured, 13_322))
      end

      [chain] = outcomes(context.caster, context.target, 14_537, 51)
      deliveries = deliveries(context.caster, chain)
      assert Enum.map(deliveries, & &1.target_guid) |> MapSet.new() == MapSet.new(context.enemy_guids)
      assert Enum.all?(deliveries, &(&1.cast_context.cast_item_guid == 42))
    end

    test "bag polymorph can backfire on its caster and both control outcomes expire", context do
      for {roll, recipient, id} <- [
            {71, context.target, 13_323},
            {78, context.caster, 13_323},
            {81, context.target, 25_189}
          ] do
        [trigger] = outcomes(context.caster, context.target, 14_537, roll)
        {controlled, _} = deliver(context.caster, recipient, trigger)
        assert Aura.has_spell?(controlled, id)
        if id == 13_323, do: assert(controlled.unit.display_id != recipient.unit.display_id)
        if id == 25_189, do: assert(Aura.has_aura?(controlled, :mod_stun))
        {expired, _} = Aura.tick(controlled, 61_001)
        refute Aura.has_spell?(expired, id)
        assert expired.unit.display_id == recipient.unit.display_id
      end
    end

    test "the bag's felhound belongs to the caster and has a thirty-second guardian lifetime", context do
      [trigger] = outcomes(context.caster, context.target, 14_537, 96)
      {_, events} = deliver(context.caster, context.caster, trigger)

      assert [%Effects.SummonGuardians{entry: 9556, count: 1, duration_ms: 30_000, cast_item_guid: 42}] = events
    end
  end

  defp outcomes(caster, target, id, roll) do
    spell = Map.fetch!(caster.internal.spellbook, id)
    context = %{CastContext.from_caster(caster, spell, target.object.guid) | cast_item_guid: 42}
    {_, [%RandomChoice{} = choice]} = SpellEffect.receive(target, context, spell, 0)
    RandomChoice.select(choice, roll)
  end

  defp deliveries(caster, trigger),
    do: Spells.resolve(caster, trigger) |> Enum.filter(&is_struct(&1, Effects.DeliverSpell))

  defp deliver(caster, target, trigger) do
    assert [%Effects.DeliverSpell{target_guid: guid, cast_context: context, spell: spell}] = deliveries(caster, trigger)
    assert guid == target.object.guid
    assert context.cast_item_guid == 42
    SpellEffect.receive(target, %{context | hit_chance_bonus: 100}, spell, 1_000)
  end

  defp entities(_context) do
    world = WorldRef.instance(0, System.unique_integer([:positive]))
    spells = Map.new(@spells, &{&1, SpellLoader.load(&1)})

    unit = %Unit{
      health: 1_000,
      max_health: 1_000,
      max_power1: 800,
      level: 60,
      faction_template: 1,
      auras: [],
      display_id: 49,
      native_display_id: 49
    }

    internal = %Internal{world: world, spellbook: spells}
    movement = struct!(%MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, movement_flags: 0}, MovementBlock.player_speeds())

    caster = %Character{
      object: %Object{guid: Guid.from_low_guid(:player, System.unique_integer([:positive]))},
      unit: unit,
      player: %Player{},
      internal: internal,
      movement_block: movement
    }

    enemies =
      for _ <- 1..3 do
        %Mob{
          object: %Object{guid: Guid.runtime(:mob, 1)},
          unit: %{unit | faction_template: 14},
          internal: internal,
          movement_block: movement
        }
      end

    for entity <- [caster | enemies] do
      guid = entity.object.guid
      type = if entity == caster, do: :players, else: :mobs
      SpatialHash.insert(type, guid, world, 0.0, 0.0, 0.0)

      Metadata.put(guid, %{
        alive?: true,
        level: 60,
        faction_template: entity.unit.faction_template,
        creature_type: 7,
        no_spell_defense?: true
      })

      on_exit(fn ->
        SpatialHash.remove(type, guid)
        Metadata.delete(guid)
      end)
    end

    %{caster: caster, target: hd(enemies), enemy_guids: Enum.map(enemies, & &1.object.guid)}
  end
end
