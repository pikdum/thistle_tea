defmodule ThistleTea.Game.Entity.Logic.AuraTest do
  use ExUnit.Case, async: true

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  defp fixture_entity(opts \\ []) do
    %Mob{
      object: %Object{guid: 1},
      unit: %Unit{
        level: Keyword.get(opts, :level, 1),
        health: 100,
        max_health: 100,
        auras: []
      },
      internal: %Internal{map: 0},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }
  end

  defp apply_spell(entity, caster_guid, caster_level, spell) do
    Aura.apply_spell(entity, caster_guid, caster_level, spell, 1_000)
  end

  defp frost_armor_fixture do
    %Spell{
      id: 168,
      name: "Frost Armor",
      school: :frost,
      cast_time_ms: 0,
      duration_ms: 600_000,
      range_yards: 0.0,
      mana_cost: 0,
      gcd_ms: 1500,
      attributes: MapSet.new(),
      effects: [
        %Effect{
          index: 1,
          type: :apply_aura,
          base_points: 29,
          die_sides: 0,
          aura: :mod_resistance,
          amplitude_ms: 0,
          misc_value: 1,
          implicit_target_a: :caster
        }
      ]
    }
  end

  defp root_spell do
    %Spell{
      id: 122,
      name: "Frost Nova",
      school: :frost,
      duration_ms: 8_000,
      effects: [
        %Effect{
          index: 0,
          type: :apply_aura,
          base_points: 0,
          die_sides: 0,
          aura: :mod_root
        }
      ]
    }
  end

  describe "apply_spell/5" do
    test "appends a holder with the spell to the unit" do
      entity = fixture_entity()
      spell = frost_armor_fixture()

      {entity, _events} = apply_spell(entity, 1, 1, spell)

      assert [%Holder{spell: ^spell, caster_guid: 1, slot: 0}] = entity.unit.auras
    end

    test "applies mod_resistance to the matching school field" do
      entity = fixture_entity()
      spell = frost_armor_fixture()

      {entity, _events} = apply_spell(entity, 1, 1, spell)

      assert entity.unit.normal_resistance == 29
      assert entity.unit.holy_resistance == 0
    end

    test "layers mod_resistance on top of base resistance" do
      entity = put_in(fixture_entity().unit.normal_resistance, 7)
      spell = frost_armor_fixture()

      {entity, _events} = apply_spell(entity, 1, 1, spell)

      assert entity.unit.base_normal_resistance == 7
      assert entity.unit.normal_resistance == 36
    end

    test "packs spell_id into the aura wire field at the holder slot" do
      entity = fixture_entity()
      spell = frost_armor_fixture()

      {entity, _events} = apply_spell(entity, 1, 1, spell)

      assert <<spell_at_slot_0::little-size(32), _rest::binary>> =
               <<entity.unit.aura::little-size(48 * 32)>>

      assert spell_at_slot_0 == spell.id
    end

    test "marks the entity for broadcast" do
      entity = fixture_entity()
      spell = frost_armor_fixture()

      {entity, _events} = apply_spell(entity, 1, 1, spell)

      assert entity.internal.broadcast_update? == true
    end

    test "applying twice fills two slots" do
      entity = fixture_entity()
      spell = frost_armor_fixture()

      {entity, _events} = apply_spell(entity, 1, 1, spell)
      {entity, _events} = apply_spell(entity, 2, 1, spell)

      assert length(entity.unit.auras) == 2
      assert Enum.map(entity.unit.auras, & &1.slot) == [0, 1]
      assert entity.unit.normal_resistance == 58
    end

    test "root aura halts active movement and emits a movement stop event" do
      entity =
        fixture_entity()
        |> put_in([Access.key!(:movement_block), Access.key!(:movement_flags)], 0x00400001)
        |> put_in([Access.key!(:movement_block), Access.key!(:duration)], 10_000)
        |> put_in([Access.key!(:movement_block), Access.key!(:spline_nodes)], [{10.0, 0.0, 0.0}])
        |> put_in([Access.key!(:movement_block), Access.key!(:spline_id)], 7)
        |> put_in([Access.key!(:internal), Access.key!(:movement_start_time)], ThistleTea.Game.Time.now())
        |> put_in([Access.key!(:internal), Access.key!(:movement_start_position)], {0.0, 0.0, 0.0})

      spell = root_spell()

      {entity, events} = apply_spell(entity, 999, 1, spell)

      assert [%{type: :movement_stopped}, %{type: :movement_root_changed, rooted?: true}] = events
      assert (entity.movement_block.movement_flags &&& 0x08000000) != 0
      assert (entity.movement_block.movement_flags &&& 0x00400001) == 0
      assert entity.movement_block.spline_nodes == []
      assert entity.internal.movement_start_time == nil
    end

    test "expiring root aura emits an unroot event" do
      entity = fixture_entity()
      spell = root_spell()

      {entity, _events} = apply_spell(entity, 999, 1, spell)
      future = entity.unit.auras |> hd() |> Map.fetch!(:expires_at)
      {entity, events} = Aura.expire_due(entity, future + 1)

      assert [%{type: :movement_root_changed, rooted?: false}] = events
      assert (entity.movement_block.movement_flags &&& 0x08000000) == 0
    end
  end

  describe "tick/2 with periodic_damage" do
    defp dot_fixture do
      %Spell{
        id: 11_366,
        name: "Pyroblast",
        school: :fire,
        cast_time_ms: 6_000,
        duration_ms: 12_000,
        range_yards: 40.0,
        mana_cost: 0,
        gcd_ms: 1500,
        attributes: MapSet.new(),
        effects: [
          %Effect{
            index: 1,
            type: :apply_aura,
            base_points: 50,
            die_sides: 0,
            aura: :periodic_damage,
            amplitude_ms: 3_000,
            misc_value: 0,
            implicit_target_a: :target_enemy
          }
        ]
      }
    end

    test "applies damage when amplitude elapses and advances the tick" do
      entity = fixture_entity()
      spell = dot_fixture()
      {entity, _events} = apply_spell(entity, 999, 1, spell)

      [holder] = entity.unit.auras
      [aura] = holder.auras
      first_tick_at = aura.next_tick_at

      {entity, events} = Aura.tick(entity, first_tick_at)

      assert entity.unit.health == 50
      assert [%{type: :spell_damage, damage: 50, periodic?: true}] = events
      [updated] = entity.unit.auras
      [updated_aura] = updated.auras
      amplitude = spell.effects |> hd() |> Map.fetch!(:amplitude_ms)
      assert updated_aura.next_tick_at == first_tick_at + amplitude
    end

    test "does not tick before amplitude has elapsed" do
      entity = fixture_entity()
      spell = dot_fixture()
      {entity, _events} = apply_spell(entity, 999, 1, spell)

      [holder] = entity.unit.auras
      [aura] = holder.auras
      before = aura.next_tick_at - 1

      {entity, events} = Aura.tick(entity, before)

      assert entity.unit.health == 100
      assert events == []
    end

    test "catches up multiple missed ticks in one call" do
      entity = fixture_entity()
      spell = dot_fixture()
      {entity, _events} = apply_spell(entity, 999, 1, spell)

      [holder] = entity.unit.auras
      [aura] = holder.auras
      far_future = aura.next_tick_at + 7_000

      {entity, _events} = Aura.tick(entity, far_future)

      [updated] = entity.unit.auras
      [updated_aura] = updated.auras
      assert updated_aura.next_tick_at > far_future
    end
  end

  describe "reactions/3" do
    test "returns trigger spell events for on-hit proc auras" do
      entity = fixture_entity()

      spell = %Spell{
        id: 168,
        name: "Frost Armor",
        school: :frost,
        duration_ms: 600_000,
        effects: [
          %Effect{
            index: 0,
            type: :apply_aura,
            base_points: 0,
            die_sides: 0,
            aura: :damage_shield,
            trigger_spell_id: 6136
          }
        ]
      }

      {entity, _events} = apply_spell(entity, 1, 10, spell)

      assert [
               %{
                 type: :trigger_spell,
                 source_guid: 1,
                 source_level: 10,
                 target_guid: 999,
                 spell_id: 6136
               }
             ] = Aura.reactions(entity, :hit_taken, %{attacker_guid: 999})
    end
  end

  describe "movement speed modifiers" do
    test "mod_decrease_speed layers on top of base movement speeds" do
      entity = %{
        fixture_entity()
        | movement_block: %MovementBlock{
            position: {0.0, 0.0, 0.0, 0.0},
            walk_speed: 2.5,
            run_speed: 7.0,
            run_back_speed: 4.5,
            swim_speed: 4.7,
            swim_back_speed: 2.5
          }
      }

      spell = %Spell{
        id: 6136,
        name: "Chilled",
        school: :frost,
        duration_ms: 5_000,
        effects: [
          %Effect{
            index: 1,
            type: :apply_aura,
            base_points: -31,
            die_sides: 1,
            aura: :mod_decrease_speed
          }
        ]
      }

      {entity, events} = apply_spell(entity, 1, 1, spell)

      assert entity.movement_block.base_run_speed == 7.0
      assert_in_delta entity.movement_block.run_speed, 4.9, 0.000001
      assert [%{type: :movement_speed_changed, speed: speed}] = events
      assert_in_delta speed, 4.9, 0.000001
    end

    test "expiring mod_decrease_speed restores base movement speeds" do
      entity = %{
        fixture_entity()
        | movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, run_speed: 7.0}
      }

      spell = %Spell{
        id: 6136,
        name: "Chilled",
        school: :frost,
        duration_ms: 5_000,
        effects: [
          %Effect{
            index: 1,
            type: :apply_aura,
            base_points: -31,
            die_sides: 1,
            aura: :mod_decrease_speed
          }
        ]
      }

      {entity, _events} = apply_spell(entity, 1, 1, spell)
      future = entity.unit.auras |> hd() |> Map.fetch!(:expires_at)
      {entity, events} = Aura.expire_due(entity, future + 1)

      assert entity.movement_block.base_run_speed == 7.0
      assert entity.movement_block.run_speed == 7.0
      assert [%{type: :movement_speed_changed, speed: 7.0}] = events
    end
  end

  describe "expire_due/2" do
    test "removes expired holders and reverses their mods" do
      entity = fixture_entity()
      spell = frost_armor_fixture()
      {entity, _events} = apply_spell(entity, 1, 1, spell)

      future = entity.unit.auras |> hd() |> Map.fetch!(:expires_at)
      {entity, _events} = Aura.expire_due(entity, future + 1)

      assert entity.unit.auras == []
      assert entity.unit.normal_resistance == 0
    end

    test "removing expired holders preserves base resistance" do
      entity = put_in(fixture_entity().unit.normal_resistance, 7)
      spell = frost_armor_fixture()
      {entity, _events} = apply_spell(entity, 1, 1, spell)

      future = entity.unit.auras |> hd() |> Map.fetch!(:expires_at)
      {entity, _events} = Aura.expire_due(entity, future + 1)

      assert entity.unit.auras == []
      assert entity.unit.base_normal_resistance == 7
      assert entity.unit.normal_resistance == 7
    end

    test "keeps non-expired holders" do
      entity = fixture_entity()
      spell = frost_armor_fixture()
      {entity, _events} = apply_spell(entity, 1, 1, spell)

      now = entity.unit.auras |> hd() |> Map.fetch!(:applied_at)
      {entity, _events} = Aura.expire_due(entity, now + 1)

      assert length(entity.unit.auras) == 1
      assert entity.unit.normal_resistance == 29
    end
  end
end
