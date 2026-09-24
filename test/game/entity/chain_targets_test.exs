defmodule ThistleTea.Game.Entity.ChainTargetsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.ChainTargets
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.System.Party, as: PartySystem
  alias ThistleTea.Game.WorldRef

  setup [:build_caster]

  describe "expand/4" do
    test "checks line of sight from each preceding jump and never revisits targets", %{caster: caster} do
      first = target(:enemy, 4.0)
      blocked = target(:enemy, 5.0)
      second = target(:enemy, 13.0)
      third = target(:enemy, 22.0)

      los? = fn source, target ->
        send(self(), {:los, source, target})
        target != blocked
      end

      assert ChainTargets.expand(caster, spell(:target_enemy), [first], line_of_sight?: los?) == [first, second, third]
      assert_received {:los, ^first, ^blocked}
      assert_received {:los, ^second, ^third}
    end

    test "honors the line-of-sight exemption", %{caster: caster} do
      first = target(:enemy, 4.0)
      second = target(:enemy, 5.0)
      spell = %{spell(:target_enemy) | attributes: MapSet.new([:ignore_line_of_sight])}

      assert ChainTargets.expand(caster, spell, [first], line_of_sight?: fn _, _ -> flunk("unexpected LOS") end) == [
               first,
               second
             ]
    end

    test "rejects dead hidden incompatible and foreign-copy targets", %{caster: caster} do
      first = target(:enemy, 4.0)
      dead = target(:enemy, 5.0, %{alive?: false})
      hidden = target(:enemy, 5.0, %{stealthed?: true, stealth_skill: 1_000, level: 60})
      wrong_type = target(:enemy, 5.0, %{creature_type: 2})
      foreign = target(:enemy, 5.0)
      SpatialHash.update(:mobs, foreign, WorldRef.instance(0, 12), 5.0, 0.0, 0.0)
      valid = target(:enemy, 8.0)
      spell = %{spell(:target_enemy) | target_creature_type_mask: 1}
      assert expand(caster, spell, first) == [first, valid]
      refute Enum.any?(expand(caster, spell, first), &(&1 in [dead, hidden, wrong_type, foreign]))
    end

    test "healing skips full health and ranks by missing health instead of percentage", %{caster: caster} do
      first = target(:friend, 4.0)
      _full = target(:friend, 5.0, %{health_deficit: 0})
      small = target(:friend, 6.0, %{health_deficit: 100, health_pct: 10})
      large = target(:friend, 7.0, %{health_deficit: 1_000, health_pct: 70})
      assert expand(caster, spell(:chain_heal), first) == [first, large, small]
    end

    test "healing prioritizes the preceding target's raidmates", %{caster: caster} do
      first = target(:friend, 4.0)
      member = target(:friend, 6.0, %{health_deficit: 50})
      outsider = target(:friend, 7.0, %{health_deficit: 1_000})
      :ok = PartySystem.invite(first, "First", member)
      {:ok, _group} = PartySystem.accept(member, "Member")
      on_exit(fn -> Enum.each([first, member], &PartySystem.leave/1) end)

      assert expand(caster, spell(:chain_heal), first) == [first, member, outsider]
    end

    test "healing can return to its injured caster and stops at the jump radius", %{caster: caster} do
      first = target(:friend, 9.0)
      _distant = target(:friend, 20.0, %{health_deficit: 1_000})
      Metadata.update(caster.object.guid, %{health_deficit: 500})
      assert expand(caster, spell(:chain_heal), first) == [first, caster.object.guid]
    end
  end

  describe "cast completion" do
    test "launch and multi-effect deliveries share one capped selection", %{caster: source} do
      candidates = for x <- 1..6, do: target(:enemy, x * 1.0)
      selected = List.last(candidates)

      caster = %Mob{
        object: %Object{guid: source.object.guid},
        unit: %Unit{health: 1_000, max_health: 1_000, level: 60, auras: []},
        internal: source.internal,
        movement_block: source.movement_block
      }

      spell = %Spell{
        id: 900_712,
        school: :physical,
        max_targets: 4,
        cast_time_ms: 1_000,
        effects: [
          %Effect{
            index: 0,
            type: :school_damage,
            base_points: 10,
            implicit_target_a: :aoe_enemy_at_caster,
            radius_yards: 10.0
          },
          %Effect{
            index: 1,
            type: :apply_aura,
            aura: :mod_attack_speed,
            base_points: -10,
            implicit_target_a: :aoe_enemy_at_caster,
            radius_yards: 10.0
          }
        ]
      }

      casting = Casting.start(caster, spell, Target.unit(selected), 1_000)
      finished = Casting.complete(casting, 2_000)
      go = Enum.find(finished.internal.events, &is_struct(&1, Effects.SpellGo))
      deliveries = for %Effects.DeliverSpell{} = effect <- finished.internal.events, do: effect
      assert length(go.hit_guids) == 4
      assert selected in go.hit_guids
      assert go.misses == []
      assert Enum.map(deliveries, & &1.target_guid) == go.hit_guids
      assert Enum.all?(deliveries, &(&1.spell.effects == spell.effects))
      assert Enum.all?(go.hit_guids, &(&1 in candidates))

      cancelled = Casting.cancel(casting, 1_500)
      refute Enum.any?(cancelled.internal.events, &is_struct(&1, Effects.DeliverSpell))
    end

    test "publishes ordered hits and retains distinct jump amounts for delivery", %{caster: source} do
      first = target(:enemy, 4.0)
      second = target(:enemy, 13.0)
      third = target(:enemy, 22.0)

      caster = %Mob{
        object: %Object{guid: source.object.guid},
        unit: %Unit{health: 1_000, max_health: 1_000, level: 60, auras: []},
        internal: source.internal,
        movement_block: source.movement_block
      }

      effect = %Effect{
        index: 0,
        type: :school_damage,
        base_points: 200,
        implicit_target_a: :target_enemy,
        chain_targets: 3,
        damage_multiplier: 0.5
      }

      spell = %Spell{
        id: 900_711,
        max_targets: 1,
        school: :nature,
        dmg_class: 0,
        cast_time_ms: 1_000,
        attributes: MapSet.new([:ignore_line_of_sight]),
        effects: [effect]
      }

      casting = Casting.start(caster, spell, Target.unit(first), 1_000)
      refute Enum.any?(casting.internal.events, &is_struct(&1, Effects.DeliverSpell))
      finished = Casting.complete(casting, 2_000)
      assert finished.internal.casting == nil
      assert Enum.any?(finished.internal.events, &match?(%Effects.SpellGo{hit_guids: [^first, ^second, ^third]}, &1))
      deliveries = for %Effects.DeliverSpell{} = effect <- finished.internal.events, do: effect
      assert Enum.map(deliveries, & &1.target_guid) == [first, second, third]
      assert Enum.map(deliveries, & &1.cast_context.chain_effects) == [%{0 => 1.0}, %{0 => 0.5}, %{0 => 0.25}]
      cancelled = Casting.cancel(casting, 1_500)
      refute Enum.any?(cancelled.internal.events, &is_struct(&1, Effects.DeliverSpell))
    end
  end

  defp expand(caster, spell, first) do
    ChainTargets.expand(caster, spell, [first], line_of_sight?: fn _, _ -> true end)
  end

  defp spell(target) do
    %Spell{effects: [%Effect{index: 0, implicit_target_a: target, chain_targets: 3}]}
  end

  defp build_caster(_context) do
    guid = target(:friend, 0.0, %{health_deficit: 0})

    %{
      caster: %{
        object: %{guid: guid},
        internal: %Internal{world: WorldRef.open(0)},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }
    }
  end

  defp target(allegiance, x, metadata \\ %{}) do
    {type, table, faction} =
      if allegiance == :friend do
        {:player, :players, %FactionTemplate{id: 1, faction: 1, faction_group: 1, friend_group: 1, enemy_group: 2}}
      else
        {:mob, :mobs, %FactionTemplate{id: 2, faction: 2, faction_group: 2, friend_group: 2, enemy_group: 1}}
      end

    guid =
      if type == :player,
        do: Guid.from_low_guid(:player, System.unique_integer([:positive])),
        else: Guid.runtime(type, 1)

    SpatialHash.update(table, guid, 0, x, 0.0, 0.0)

    Metadata.put(
      guid,
      Map.merge(
        %{
          alive?: true,
          unit_flags: 0,
          faction_template: faction,
          faction_can_have_reputation?: false,
          health_deficit: 0,
          creature_type: 1
        },
        metadata
      )
    )

    on_exit(fn ->
      SpatialHash.remove(table, guid)
      Metadata.delete(guid)
    end)

    guid
  end
end
