defmodule ThistleTea.Game.Entity.Logic.ShadowguardDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EffectResolver.Spells
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.ProcRule
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellChain
  alias ThistleTea.Game.World.Loader.SpellProcEvent
  alias ThistleTea.Game.World.Loader.SpellThreat
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.WorldRef

  @moduletag :dbc_db
  @ranks [
    {18_137, 28_377, 20},
    {19_308, 28_378, 35},
    {19_309, 28_379, 51},
    {19_310, 28_380, 70},
    {19_311, 28_381, 90},
    {19_312, 28_382, 116}
  ]

  setup [:catalog, :combatants]

  describe "receive/4" do
    test "Lightning Shield retaliation cannot counter-proc Shadowguard", context do
      {priest, _} = Aura.apply_spell(context.priest, 1, 60, SpellLoader.load(19_312), 0)
      lightning = Effects.trigger_spell(context.attacker.object.guid, 60, 1, 26_364, triggered_by_spell_id: 10_394)
      delivery = context.attacker |> Spells.resolve(lightning) |> Enum.find(&is_struct(&1, Effects.DeliverSpell))
      cast = %{delivery.cast_context | hit_outcome: :hit}
      {hit, events} = SpellEffect.receive(priest, cast, delivery.spell, 1_000)
      assert hit.unit.health < priest.unit.health
      assert hd(hit.unit.auras).charges == 3
      refute Enum.any?(events, &is_struct(&1, Effects.TriggerSpell))
      assert Enum.any?(events, &match?(%Effects.SpellDamage{proc_origin: :suppressed}, &1))

      {hit, events} =
        SpellEffect.receive(
          hit,
          %CastContext{caster_guid: context.attacker.object.guid, caster_level: 60},
          SpellLoader.load(8042),
          5_000
        )

      assert hd(hit.unit.auras).charges == 2
      assert Enum.any?(events, &match?(%Effects.TriggerSpell{spell_id: 28_382}, &1))
    end

    test "a spell absorbed by Power Word Shield still consumes a Shadowguard charge", context do
      {priest, _} = Aura.apply_spell(context.priest, 1, 60, SpellLoader.load(19_312), 0)
      {priest, _} = Aura.apply_spell(priest, 1, 60, SpellLoader.load(17), 0)
      bolt = SpellLoader.load(686)
      cast_context = %CastContext{caster_guid: context.attacker.object.guid, caster_level: 60}
      {priest, events} = SpellEffect.receive(priest, cast_context, bolt, 1_000)
      assert priest.unit.health == 5_000
      assert Enum.any?(events, &match?(%Effects.SpellDamage{damage: damage, absorbed: damage} when damage > 0, &1))
      assert Enum.count(events, &match?(%Effects.TriggerSpell{spell_id: 28_382}, &1)) == 1
      assert Enum.find(priest.unit.auras, &(&1.spell.id == 19_312)).charges == 2
    end
  end

  describe "receive_attack/4" do
    test "all ranks damage the attacker through triggered delivery without damage threat", context do
      for {id, trigger, amount} <- @ranks do
        spell = SpellLoader.load(id)
        assert %ProcRule{proc_ex: 0x403, cooldown_ms: 3_500} = spell.proc_rule
        {priest, _} = Aura.apply_spell(context.priest, 1, 60, spell, 0)
        {priest, events} = hit(priest, context.attacker.object.guid, 1_000)
        assert [%{charges: 2, next_proc_at: 4_500}] = priest.unit.auras
        proc = Enum.find(events, &is_struct(&1, Effects.TriggerSpell))
        assert proc.spell_id == trigger
        assert proc.triggering_spell_id == id
        delivery = priest |> Spells.resolve(proc) |> Enum.find(&is_struct(&1, Effects.DeliverSpell))
        assert delivery.target_guid == context.attacker.object.guid
        assert delivery.cast_context.spell_threat.multiplier == 0.0
        cast_context = %{delivery.cast_context | hit_outcome: :hit}
        {attacker, events} = SpellEffect.receive(context.attacker, cast_context, delivery.spell, 1_000)
        assert attacker.unit.health == 5_000 - amount
        assert Map.get(attacker.internal.threat, priest.object.guid, 0) == 0
        assert Enum.any?(events, &match?(%Effects.SpellDamage{spell: %{id: ^trigger}, damage: ^amount}, &1))
      end
    end

    test "attackers share the cooldown and the third charge removes the aura", context do
      {priest, _} = Aura.apply_spell(context.priest, 1, 60, SpellLoader.load(19_312), 0)
      {priest, events} = hit(priest, 2, 1_000)
      assert Enum.count(events, &is_struct(&1, Effects.TriggerSpell)) == 1
      {priest, events} = hit(priest, 3, 4_499)
      refute Enum.any?(events, &is_struct(&1, Effects.TriggerSpell))
      assert [%{charges: 2, next_proc_at: 4_500}] = priest.unit.auras
      {priest, events} = hit(priest, 3, 4_500)
      assert Enum.any?(events, &match?(%Effects.TriggerSpell{target_guid: 3}, &1))
      assert [%{charges: 1, next_proc_at: 8_000}] = priest.unit.auras
      {priest, events} = hit(priest, 2, 8_000)
      assert Enum.count(events, &is_struct(&1, Effects.TriggerSpell)) == 1
      assert priest.unit.auras == []
      {_priest, events} = hit(priest, 2, 12_000)
      refute Enum.any?(events, &is_struct(&1, Effects.TriggerSpell))
    end

    test "expiry and death remove the retaliatory aura", context do
      {priest, _} = Aura.apply_spell(context.priest, 1, 60, SpellLoader.load(19_312), 0)
      assert [%{charges: 3, expires_at: 600_000}] = priest.unit.auras
      {expired, _} = Aura.expire_due(priest, 600_000)
      assert expired.unit.auras == []
      assert Core.take_damage(priest, 5_000, 1_000).unit.auras == []
      {dead, events} = Combat.receive_attack(priest, %{caster: 2, damage: 5_000}, 1_000, roll: 9_999)
      assert dead.unit.health == 0
      refute Enum.any?(events, &is_struct(&1, Effects.TriggerSpell))
    end
  end

  defp hit(priest, attacker_guid, now) do
    Combat.receive_attack(priest, %{caster: attacker_guid, caster_level: 60, damage: 5}, now, roll: 9_999)
  end

  defp catalog(_context) do
    chains =
      @ranks
      |> Enum.with_index(1)
      |> Enum.map(fn {{id, _trigger, _amount}, rank} ->
        {SpellChain, {:chain, id}, %{first_spell: 18_137, rank: rank, prev_spell: 0, req_spell: 0}}
      end)

    triggers =
      Enum.flat_map(@ranks, fn {_id, trigger, _amount} ->
        [{SpellChain, {:chain, trigger}, nil}, {SpellThreat, trigger, %{threat: 0.0, multiplier: 0.0}}]
      end)

    for {table, key, value} <- [
          {SpellProcEvent, 18_137, %ProcRule{proc_ex: 0x403, cooldown_ms: 3_500}}
          | chains ++ triggers ++ [{SpellChain, {:chain, 17}, nil}, {SpellChain, {:chain, 686}, nil}]
        ] do
      previous = :ets.lookup(table, key)
      :ets.insert(table, {key, value})

      on_exit(fn ->
        :ets.delete(table, key)
        :ets.insert(table, previous)
      end)
    end

    :ok
  end

  defp combatants(_context) do
    unit = %Unit{level: 60, health: 5_000, max_health: 5_000, normal_resistance: 0, auras: []}
    movement = %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}

    priest = %Character{
      object: %Object{guid: 1},
      unit: unit,
      player: %Player{},
      internal: %Internal{},
      movement_block: movement
    }

    guid = System.unique_integer([:positive]) + 50_000_000

    attacker = %Mob{
      object: %Object{guid: guid},
      unit: unit,
      internal: %Internal{world: WorldRef.open(0), threat: %{}},
      movement_block: movement
    }

    Metadata.put(guid, %{alive?: true, level: 60})
    on_exit(fn -> Metadata.delete(guid) end)
    %{priest: priest, attacker: attacker}
  end
end
