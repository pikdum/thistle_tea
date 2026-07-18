defmodule ThistleTea.Game.Entity.Logic.CoreTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Loot
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Spell

  describe "heal/2" do
    test "restores health up to max health" do
      entity = entity(health: 40, max_health: 100)

      entity = Core.heal(entity, 75)

      assert entity.unit.health == 100
      assert entity.internal.broadcast_update? == true
    end

    test "ignores non-positive amounts" do
      entity = entity(health: 40, max_health: 100)

      assert Core.heal(entity, 0) == entity
    end
  end

  describe "take_damage_with_absorb/4 killer recording" do
    test "records the source on the killing blow" do
      entity = damageable(health: 30)

      {entity, _absorbed} = Core.take_damage_with_absorb(entity, 30, 1_000, source: 777)

      assert Core.dead?(entity)
      assert entity.internal.killed_by == 777
    end

    test "does not record a killer when the damage is not lethal" do
      entity = damageable(health: 30)

      {entity, _absorbed} = Core.take_damage_with_absorb(entity, 10, 1_000, source: 777)

      refute Core.dead?(entity)
      assert entity.internal.killed_by == nil
    end

    test "records nothing on a kill when no source is given" do
      entity = damageable(health: 30)

      {entity, _absorbed} = Core.take_damage_with_absorb(entity, 30, 1_000)

      assert Core.dead?(entity)
      assert entity.internal.killed_by == nil
    end

    test "ignores a zero source guid" do
      entity = damageable(health: 30)

      {entity, _absorbed} = Core.take_damage_with_absorb(entity, 30, 1_000, source: 0)

      assert entity.internal.killed_by == nil
    end
  end

  describe "take_damage_with_absorb/4 aura cleanup" do
    test "keeps passive auras and removes temporary auras on death" do
      passive = %Holder{slot: 0, spell: %Spell{id: 1, attributes: MapSet.new([:passive])}}
      temporary = %Holder{slot: 1, spell: %Spell{id: 2, attributes: MapSet.new()}}
      entity = damageable(health: 30)
      entity = %{entity | unit: %{entity.unit | auras: [passive, temporary]}}

      {entity, _absorbed} = Core.take_damage_with_absorb(entity, 30, 1_000)

      assert entity.unit.auras == [passive]
    end
  end

  describe "take_damage_with_absorb/4 death items" do
    test "rewards one DBC-defined item to an eligible tapped caster" do
      holder = %Holder{
        caster_guid: 777,
        caster_level: 10,
        auras: [%Aura{type: :channel_death_item, item_type: 6265, amount: 0}]
      }

      duplicate = %{holder | spell: %Spell{id: 17_877}}
      entity = damageable(health: 30)
      unit = %{entity.unit | level: 10, auras: [holder, duplicate]}
      internal = %{entity.internal | loot: %Loot{tapped_by: %{player: 777}}}

      {entity, _absorbed} =
        Core.take_damage_with_absorb(%{entity | unit: unit, internal: internal}, 30, 1_000, source: 777)

      assert [%{type: :create_item, target_guid: 777, item_id: 6265, count: 1}] = entity.internal.events
    end

    test "does not reward death items for gray or differently tapped creatures" do
      holder = %Holder{
        caster_guid: 777,
        caster_level: 60,
        auras: [%Aura{type: :channel_death_item, item_type: 6265, amount: 1}]
      }

      for {victim_level, tapped_player} <- [{50, 777}, {60, 778}] do
        entity = damageable(health: 30)
        unit = %{entity.unit | level: victim_level, auras: [holder]}
        internal = %{entity.internal | loot: %Loot{tapped_by: %{player: tapped_player}}}

        {entity, _absorbed} =
          Core.take_damage_with_absorb(%{entity | unit: unit, internal: internal}, 30, 1_000, source: 777)

        assert entity.internal.events in [nil, []]
      end
    end
  end

  describe "take_damage_with_absorb/4 self resurrection" do
    test "offers Reincarnation after lethal damage when learned" do
      entity = damageable(health: 30)
      entity = %{entity | internal: %{entity.internal | spellbook: %{20_608 => %Spell{id: 20_608}}}}
      entity = Map.put(entity, :player, %Player{})

      {entity, _absorbed} = Core.take_damage_with_absorb(entity, 30, 1_000)

      assert entity.player.self_res_spell == 21_169
    end
  end

  describe "should_tether?/2" do
    test "returns true when outside tether range after timeout" do
      entity = entity(position: {100.0, 0.0, 0.0, 0.0}, last_hostile_time: 1_000)

      assert Core.should_tether?(entity, 7_000)
    end

    test "returns false inside tether range" do
      entity = entity(position: {10.0, 0.0, 0.0, 0.0}, last_hostile_time: 1_000)

      refute Core.should_tether?(entity, 7_000)
    end

    test "returns false before timeout" do
      entity = entity(position: {100.0, 0.0, 0.0, 0.0}, last_hostile_time: 1_000)

      refute Core.should_tether?(entity, 6_999)
    end

    test "tethers immediately when outside an explicit leash range" do
      entity = entity(position: {60.0, 0.0, 0.0, 0.0}, last_hostile_time: 1_000, leash_range: 50.0)

      assert Core.should_tether?(entity, 1_500)
    end

    test "stays inside an explicit leash range even beyond the level formula" do
      entity = entity(position: {100.0, 0.0, 0.0, 0.0}, last_hostile_time: 1_000, leash_range: 120.0)

      refute Core.should_tether?(entity, 7_000)
    end
  end

  describe "tether_range/1" do
    test "uses the explicit leash range when set" do
      assert Core.tether_range(entity(leash_range: 120.0)) == 120.0
    end

    test "falls back to the level formula when the leash range is unset" do
      assert Core.tether_range(entity([])) == 42
    end
  end

  defp entity(opts) do
    %{
      unit: %Unit{
        health: Keyword.get(opts, :health),
        max_health: Keyword.get(opts, :max_health),
        level: 1
      },
      internal: %Internal{
        spawn: %Spawn{position: {0.0, 0.0, 0.0}},
        last_hostile_time: Keyword.get(opts, :last_hostile_time),
        creature: %Creature{leash_range: Keyword.get(opts, :leash_range, 0.0)}
      },
      movement_block: %MovementBlock{position: Keyword.get(opts, :position)}
    }
  end

  defp damageable(opts) do
    %{
      unit: %Unit{health: Keyword.get(opts, :health), max_health: 100, level: 1, auras: []},
      internal: %Internal{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, spline_nodes: []}
    }
  end
end
