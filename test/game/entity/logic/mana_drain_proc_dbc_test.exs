defmodule ThistleTea.Game.Entity.Logic.ManaDrainProcDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.EffectResolver.Spells
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.AttackFeedback
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.EquipmentAuras
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellChain
  alias ThistleTea.Game.World.Loader.SpellEffectOverride
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.WorldRef

  @moduletag :dbc_db

  setup [:catalog, :combatants]

  describe "receive/4" do
    test "equipment procs independently energize and leech through the caster owner", context do
      for {mana, expected_gain} <- [{100, 16}, {3, 11}, {0, 8}] do
        caster = equip(context.caster)
        victim = %{context.victim | unit: %{context.victim.unit | power1: mana}}
        [energize, drain] = deliveries(caster, victim)
        assert energize.spell.id == 29_471
        assert energize.target_guid == caster.object.guid
        assert drain.spell.id == 27_526
        assert drain.target_guid == victim.object.guid
        {caster, events} = SpellEffect.receive(caster, energize.cast_context, energize.spell, 0)
        assert caster.unit.power1 == 8
        assert [%Effects.SpellEnergize{spell_id: 29_471, amount: 8}] = events
        {victim, [%Effects.LeechPower{} = leech]} = receive_drain(victim, drain)
        assert victim.unit.power1 == max(mana - 8, 0)
        assert leech.amount == min(mana, 8)
        EventSink.emit(victim, leech)
        assert_receive {:"$gen_cast", {:leech_power, ^leech}}

        assert {:noreply, %{character: caster}, {:continue, :maybe_broadcast_update}} =
                 PlayerServer.handle_cast({:leech_power, leech}, %{character: caster})

        assert caster.unit.power1 == expected_gain
        assert caster.internal.last_mana_use_at == -100
        assert caster.unit.health == 1_000
        assert victim.unit.health == 1_000
      end
    end

    test "targets with other resources cannot prevent the self grant", context do
      caster = equip(context.caster)
      victim = %{context.victim | unit: %{context.victim.unit | power_type: 1, power2: 100}}
      [energize, drain] = deliveries(caster, victim)
      {caster, [_]} = SpellEffect.receive(caster, energize.cast_context, energize.spell, 0)
      {unchanged, []} = receive_drain(victim, drain)
      assert unchanged.unit == victim.unit
      assert caster.unit.power1 == 8
    end

    test "dead or missing victims still allow the self grant and a dead wearer cannot receive it", context do
      caster = equip(context.caster)
      Metadata.delete(context.victim.object.guid)
      assert [%Effects.DeliverSpell{target_guid: target, spell: %{id: 29_471}}] = deliveries(caster, context.victim)
      assert target == caster.object.guid
      Metadata.put(context.victim.object.guid, %{alive?: false, level: 60})
      assert [%Effects.DeliverSpell{spell: %{id: 29_471}}] = deliveries(caster, context.victim)
      dead = %{caster | unit: %{caster.unit | health: 0}}
      assert deliveries(dead, context.victim) == []
    end

    test "restoration clamps to capacity and equipment removal stops both spells", context do
      caster = equip(%{context.caster | unit: %{context.caster.unit | power1: 98}})
      [energize, drain] = deliveries(caster, context.victim)
      {caster, [_]} = SpellEffect.receive(caster, energize.cast_context, energize.spell, 0)
      assert caster.unit.power1 == 100
      {_, [leech]} = receive_drain(context.victim, drain)
      assert {:noreply, %{character: caster}, _} = PlayerServer.handle_cast({:leech_power, leech}, %{character: caster})
      assert caster.unit.power1 == 100
      assert length(equip(caster).unit.auras) == 1
      removed = EquipmentAuras.sync(caster, [], &SpellLoader.load/1, 1_000, [])
      assert removed.unit.auras == []
      assert deliveries(removed, context.victim) == []
      assert length(equip(removed).unit.auras) == 1
    end
  end

  defp receive_drain(victim, delivery) do
    SpellEffect.receive(victim, %{delivery.cast_context | hit_outcome: :hit}, delivery.spell, 0)
  end

  defp deliveries(caster, victim) do
    {caster, _} = Effects.drain(caster)
    feedback = %{victim_guid: victim.object.guid, outcome: :normal, damage: 10}
    {caster, events} = caster |> AttackFeedback.receive(feedback, 0) |> Effects.drain()

    events
    |> Enum.flat_map(&Spells.resolve(caster, &1))
    |> Enum.filter(&is_struct(&1, Effects.DeliverSpell))
  end

  defp equip(caster) do
    EquipmentAuras.sync(caster, [], &SpellLoader.load/1, 0, [{:item_equip, 777, 27_522}])
  end

  defp catalog(_context) do
    for id <- [27_522, 27_526, 29_471] do
      cache_fixture(SpellChain, {:chain, id}, nil)
      cache_fixture(SpellEffectOverride, {:coefficients, id}, {0.0, -1.0, -1.0})
      cache_fixture(SpellLoader, {:spell, id}, SpellLoader.load(id))
    end

    :ok
  end

  defp cache_fixture(table, key, value) do
    previous = :ets.lookup(table, key)
    :ets.insert(table, {key, value})

    on_exit(fn ->
      :ets.delete(table, key)
      :ets.insert(table, previous)
    end)
  end

  defp combatants(_context) do
    guid = System.unique_integer([:positive]) + 50_000_000

    caster = %Character{
      object: %Object{guid: guid},
      unit: %Unit{level: 60, health: 1_000, max_health: 1_000, power_type: 0, power1: 0, max_power1: 100, auras: []},
      player: %Player{},
      internal: %Internal{world: WorldRef.open(0), last_mana_use_at: -100},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    victim = %{caster | object: %Object{guid: guid + 1}, unit: %{caster.unit | power1: 100}}
    Metadata.put(victim.object.guid, %{alive?: true, level: 60})
    on_exit(fn -> Metadata.delete(victim.object.guid) end)
    {:ok, _} = Entity.register(caster.object.guid)
    %{caster: caster, victim: victim}
  end
end
