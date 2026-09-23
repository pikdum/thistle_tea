defmodule ThistleTea.Game.Entity.Logic.Aura.CapacityTest do
  use ExUnit.Case, async: true

  import Bitwise, only: [>>>: 2, &&&: 2]

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Aura.Change
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target

  setup [:target]

  describe "apply_spell/4" do
    test "the thirty-third buff evicts the oldest and removes its stat bonus", %{target: target} do
      target = fill(target, 32, :mod_stat, false)
      assert target.unit.intellect == 42
      {target, events} = Aura.apply_spell(target, context(), spell(900_100, :mod_stat, false, 5), 100)
      assert length(target.unit.auras) == 32
      refute Aura.has_spell?(target, 900_001)
      assert Aura.has_spell?(target, 900_100)
      assert target.unit.intellect == 46
      assert hd(target.unit.auras).slot == 1
      assert List.last(target.unit.auras).slot == 0
      assert (target.unit.aura &&& 0xFFFFFFFF) == 900_100
      assert Enum.any?(events, &match?(%Effects.AuraDuration{aura_slot: 0}, &1))
    end

    test "refreshing at capacity preserves the slot and protects the refreshed aura", %{target: target} do
      target = fill(target, 32, :mod_stat, false)
      {target, _} = Aura.apply_spell(target, context(), spell(900_001, :mod_stat, false), 100)
      assert hd(target.unit.auras).slot == 0
      {target, _} = Aura.apply_spell(target, context(), spell(900_100, :mod_stat, false), 101)
      assert Aura.has_spell?(target, 900_001)
      refute Aura.has_spell?(target, 900_002)
      assert length(target.unit.auras) == 32
    end

    test "a lower-priority buff cannot remain active without a slot", %{target: target} do
      holders = for id <- 1..32, do: holder(id, false, :dummy, expires_at: -1)
      {target, _} = Aura.transition(target, %Change{holders: holders, cause: :applied, now: 0})
      {unchanged, events} = Aura.apply_spell(target, context(), spell(900_100, :mod_stat, false, 50), 100)
      assert unchanged == target
      assert events == []
      assert unchanged.unit.intellect == 10
    end

    test "debuff overflow ends an evicted periodic effect and frees its display slot", %{target: target} do
      target = fill(target, 16, :periodic_damage, true)
      {target, _} = Aura.apply_spell(target, context(2), spell(900_100, :mod_damage_taken, true), 100)
      assert length(target.unit.auras) == 16
      refute Aura.has_spell?(target, 900_001)
      assert List.last(target.unit.auras).slot == 32
      assert (target.unit.aura >>> (32 * 32) &&& 0xFFFFFFFF) == 900_100
      {target, events} = Aura.tick(target, 1_100)
      assert target.unit.health == 985
      refute Enum.any?(events, &match?(%Effects.SpellDamage{spell_id: 900_001}, &1))
      assert Enum.count(events, &is_struct(&1, Effects.SpellDamage)) == 15
    end

    test "rejected control effects do not consume diminishing returns or apply control", %{target: target} do
      holders = for id <- 1..16, do: holder(id, true, :mod_stun)
      {target, _} = Aura.transition(target, %Change{holders: holders, cause: :applied, now: 0})
      polymorph = %{spell(118, :mod_confuse, true) | mechanic: 17}
      assert {^target, []} = Aura.apply_spell(target, context(2), polymorph, 100)
      assert target.internal.diminishing_returns == %{}
      refute Aura.has_aura?(target, :mod_confuse)
    end

    test "evicting control clears movement and begins diminishing recovery", %{target: target} do
      root = %{spell(339, :mod_root, true) | mechanic: 7}
      {target, _} = Aura.apply_spell(target, context(2), root, 0)
      target = fill(target, 15, :mod_damage_taken, true)
      assert target.internal.rooted?
      {target, events} = Aura.apply_spell(target, context(2), spell(900_100, :mod_damage_taken, true), 100)
      refute target.internal.rooted?
      refute Aura.has_spell?(target, 339)
      assert Enum.any?(events, &match?(%Effects.MovementRootChanged{rooted?: false}, &1))
      assert Enum.any?(target.internal.diminishing_returns, fn {_group, entry} -> entry.reset_at == 15_100 end)
    end

    test "stacking reuses a slot and normal expiry permits later applications", %{target: target} do
      target = fill(target, 16, :periodic_damage, true)
      stack = %{spell(900_001, :periodic_damage, true) | stack_amount: 5}
      {target, _} = Aura.apply_spell(target, context(2), stack, 100)
      assert length(target.unit.auras) == 16
      assert hd(target.unit.auras).stacks == 2
      assert hd(target.unit.auras).slot == 32
      {target, _} = Aura.expire_due(target, 60_100)
      assert target.unit.auras == []
      {target, _} = Aura.apply_spell(target, context(2), stack, 60_101)
      assert [%Holder{slot: 32, stacks: 1}] = target.unit.auras
    end

    test "item and triggered provenance reach replacement rules", %{target: target} do
      item_context = %{context() | cast_item_guid: 123, triggered?: true}
      {target, _} = Aura.apply_spell(target, item_context, spell(900_001, :mod_stat, false), 0)
      assert [%Holder{cast_item_guid: 123, triggered?: true}] = target.unit.auras
    end

    test "evicting a self-channel ends its channel and subsequent recovery ticks", %{target: target} do
      channel = %{spell(900_100, :obs_mod_health, false) | attributes: MapSet.new([:channeled])}
      target = %{target | unit: %{target.unit | health: 500}}
      target = Casting.start_triggered(target, channel, Target.self(1), 0, nil)
      assert target.unit.channel_spell == channel.id
      assert Aura.has_spell?(target, channel.id)
      target = fill(target, 32, :dummy, false)
      refute Aura.has_spell?(target, channel.id)
      assert target.internal.casting == nil
      assert target.unit.channel_spell == 0
      assert Enum.count(target.internal.events, &match?(%Effects.ChannelUpdate{channel_time_ms: 0}, &1)) == 1
      {target, _} = Aura.tick(target, 1_100)
      assert target.unit.health == 500
    end

    test "hidden persistent damage still ticks at the visible debuff limit", %{target: target} do
      target = fill(target, 16, :mod_damage_taken, true)
      area = %{spell(900_100, :periodic_damage, true) | hidden_aura?: true}
      {target, _} = Aura.apply_spell(target, context(2), area, 100)
      assert length(target.unit.auras) == 17
      assert List.last(target.unit.auras).slot == nil
      {target, events} = Aura.tick(target, 1_100)
      assert target.unit.health == 999
      assert Enum.any?(events, &match?(%Effects.SpellDamage{spell_id: 900_100, damage: 1}, &1))
      assert Enum.count(target.unit.auras, &is_integer(&1.slot)) == 16
    end
  end

  describe "transition/2" do
    test "hidden passives are exempt and both visible limits are independent", %{target: target} do
      positive = for id <- 1..33, do: holder(id, false, :dummy)
      negative = for id <- 34..50, do: holder(id, true, :dummy)
      passive = %{holder(51, false, :mod_stat) | spell: %Spell{id: 51, attributes: MapSet.new([:passive])}}
      holders = positive ++ negative ++ [passive]
      {target, _} = Aura.transition(target, %Change{holders: holders, cause: :applied, now: 100})
      assert length(target.unit.auras) == 49
      assert List.last(target.unit.auras).slot == nil
      assert Enum.count(target.unit.auras, &(&1.slot in 0..31)) == 32
      assert Enum.count(target.unit.auras, &(&1.slot in 32..47)) == 16
      dead = Core.take_damage(target, 1_000, 200)
      assert Enum.all?(dead.unit.auras, &Spell.attribute?(&1.spell, :passive))
    end
  end

  defp fill(target, count, type, negative?) do
    Enum.reduce(1..count, target, fn id, target ->
      {target, _} =
        Aura.apply_spell(target, context(if(negative?, do: 2, else: 1)), spell(900_000 + id, type, negative?), id)

      target
    end)
  end

  defp context(caster \\ 1),
    do: %CastContext{caster_guid: caster, caster_level: 60, caster_type: :player, target_hostile?: caster != 1}

  defp spell(id, type, negative?, amount \\ 1) do
    %Spell{
      id: id,
      school: :shadow,
      duration_ms: 60_000,
      custom_flags: if(negative?, do: 2, else: 4),
      effects: [
        %Effect{
          index: 0,
          type: :apply_aura,
          aura: type,
          base_points: amount,
          misc_value: 3,
          amplitude_ms: 1_000,
          implicit_target_a: if(negative?, do: :target_enemy, else: :caster)
        }
      ]
    }
  end

  defp holder(id, negative?, type, opts \\ []) do
    %Holder{
      spell: %Spell{id: 900_000 + id},
      caster_guid: 1,
      applied_at: id,
      expires_at: Keyword.get(opts, :expires_at, 60_000),
      negative?: negative?,
      auras: [%AuraData{index: 0, type: type, amount: 1, misc_value: 3}]
    }
  end

  defp target(_context) do
    %{
      target: %Character{
        object: %Object{guid: 1},
        player: %Player{},
        internal: %Internal{},
        unit: %Unit{health: 1_000, max_health: 1_000, level: 60, base_intellect: 10, intellect: 10, auras: []},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }
    }
  end
end
