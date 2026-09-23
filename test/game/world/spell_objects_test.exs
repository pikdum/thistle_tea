defmodule ThistleTea.Game.World.SpellObjectsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Condition
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate
  alias ThistleTea.Game.Entity.EffectResolver
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellTarget
  alias ThistleTea.Game.Entity.Server.GameObject, as: ObjectServer
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.ObjectTargets
  alias ThistleTea.Game.Spell.ObjectTargets.Selector
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.SpellObjectTarget
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpellObjects
  alias ThistleTea.Game.World.SpellRequirements
  alias ThistleTea.Game.WorldRef

  setup [:caster]

  describe "resolve/4" do
    test "validates explicit object presence, range and instance", %{caster: caster, spell: spell} do
      spell = %{
        spell
        | attributes: MapSet.new([:ignore_line_of_sight]),
          effects: [%Effect{index: 0, type: :activate_object, implicit_target_a: :game_object, misc_value: 7}]
      }

      near = spawn_object(100, caster.internal.world, {9.0, 0.0, 0.0})
      far = spawn_object(100, caster.internal.world, {11.0, 0.0, 0.0})
      foreign = spawn_object(100, WorldRef.instance(999, 502), {0.0, 0.0, 0.0})

      assert %ObjectTargets{by_effect: %{0 => [^near]}, error: nil} =
               SpellObjects.resolve(caster, spell, Target.object(near))

      for targets <- [Target.none(), Target.unit(caster.object.guid), Target.object(far), Target.object(foreign)] do
        assert %ObjectTargets{error: :bad_targets} = SpellObjects.resolve(caster, spell, targets)
      end
    end

    test "selects the nearest conditioned object in this copy", %{caster: caster, spell: spell} do
      spawn_object(100, WorldRef.instance(999, 502), {0.0, 0.0, 0.0})
      spawn_object(100, caster.internal.world, {0.0, 0.0, 15.0})
      far = spawn_object(100, caster.internal.world, {4.0, 0.0, 0.0})
      near = spawn_object(100, caster.internal.world, {1.0, 0.0, 0.0})
      Metadata.update(near, %{go_state: 0})
      selector = %Selector{entry: 100, condition: %Condition{entry: 1, type: :object_go_state, value1: 1}}
      spell = %{spell | object_targets: [selector]}
      assert %ObjectTargets{by_effect: %{0 => [^far]}, error: nil} = SpellObjects.resolve(caster, spell, Target.none())
      Metadata.update(near, %{go_state: 1})
      assert %ObjectTargets{by_effect: %{0 => [^near]}} = SpellObjects.resolve(caster, spell, Target.none())
    end

    test "retains area targets by effect and respects inverse masks", %{caster: caster, spell: spell} do
      one = spawn_object(100, caster.internal.world, {0.0, 0.0, 0.0})
      two = spawn_object(200, caster.internal.world, {20.0, 0.0, 0.0})
      spawn_object(100, caster.internal.world, {20.0, 0.0, 0.0})
      spawn_object(200, caster.internal.world, {20.0, 0.0, 6.0})

      spell = %{
        spell
        | effects: [
            %Effect{
              index: 0,
              type: :activate_object,
              implicit_target_a: :aoe_enemy_at_caster,
              implicit_target_b: :game_objects_at_source,
              radius_yards: 5.0,
              misc_value: 7
            },
            %Effect{
              index: 1,
              type: :activate_object,
              implicit_target_a: :game_objects_at_destination,
              radius_yards: 5.0,
              misc_value: 6
            }
          ],
          object_targets: [%Selector{entry: 100, inverse_effect_mask: 2}, %Selector{entry: 200, inverse_effect_mask: 1}]
      }

      targets = %{Target.at({20.0, 0.0, 0.0}) | source_location: {0.0, 0.0, 0.0}}

      assert %ObjectTargets{by_effect: %{0 => [^one], 1 => [^two]}} =
               resolved = SpellObjects.resolve(caster, spell, targets)

      assert [
               %Effects.SpellGameObjectAction{target_guid: ^one, action: 7},
               %Effects.SpellGameObjectAction{target_guid: ^two, action: 6}
             ] = ObjectTargets.actions(spell, resolved)

      assert SpellTarget.target_query(spell, targets) == :none
    end

    test "missing strict targets fail while optional targets remain empty", %{caster: caster, spell: spell} do
      assert %ObjectTargets{error: nil, by_effect: %{0 => []}} = SpellObjects.resolve(caster, spell, Target.none())
      assert %ObjectTargets{error: :bad_targets} = SpellObjects.resolve(caster, %{spell | id: 15_958}, Target.none())

      assert %ObjectTargets{error: :bad_targets} =
               SpellObjects.resolve(caster, %{spell | object_targets: []}, Target.none())
    end

    test "focus selectors and long ranges only see live objects in this world", %{caster: caster, spell: spell} do
      guid = spawn_object(100, caster.internal.world, {1_000.0, 0.0, 0.0})
      spell = %{spell | range_yards: 50_000.0, object_targets: [%Selector{entry: 0}]}

      assert %ObjectTargets{by_effect: %{0 => [^guid]}} =
               SpellObjects.resolve(caster, spell, Target.none(), %{guid: guid})

      stop_supervised!(guid)
      assert %ObjectTargets{by_effect: %{0 => []}} = SpellObjects.resolve(caster, spell, Target.none(), %{guid: guid})
    end
  end

  describe "cast lifecycle" do
    @tag :dbc_db
    test "triggered object spells retain object hits and concrete delivery", %{caster: caster} do
      previous = :ets.lookup(SpellObjectTarget, 18_655)
      :ets.insert(SpellObjectTarget, {18_655, [%Selector{entry: 176_557}]})

      on_exit(fn ->
        :ets.delete(SpellObjectTarget, 18_655)
        Enum.each(previous, &:ets.insert(SpellObjectTarget, &1))
      end)

      guid = spawn_object(176_557, caster.internal.world, {1.0, 0.0, 0.0})

      effects =
        EffectResolver.resolve(caster, %Effects.TriggerSpell{
          source_guid: caster.object.guid,
          source_level: 60,
          spell_id: 18_655,
          target_guid: caster.object.guid
        })

      assert [%Effects.SpellGo{hit_guids: [^guid]}, %Effects.ApplyGameObjectAction{target_guid: ^guid, action: 1}] =
               effects

      assert [%Effects.TriggerSpellRequest{source_guid: 123}] =
               EffectResolver.resolve(caster, %Effects.TriggerSpell{
                 source_guid: 123,
                 source_level: 60,
                 spell_id: 18_655,
                 target_guid: caster.object.guid
               })
    end

    test "delivery rejects a caster who changed copies after resolution", %{caster: caster} do
      guid = spawn_object(100, caster.internal.world, {1.0, 0.0, 0.0})

      [effect] =
        EffectResolver.resolve(caster, %Effects.SpellGameObjectAction{target_guid: guid, spell_id: 100, action: 7})

      moved = %{caster | internal: %{caster.internal | world: WorldRef.instance(999, 502)}}
      World.update_position(moved)
      Entity.apply_game_object_action(guid, effect)
      assert :sys.get_state(Entity.pid(guid)).game_object.flags == 0
      World.update_position(caster)
    end

    test "revalidates launch before costs when a required object disappears", %{caster: caster, spell: spell} do
      guid = spawn_object(100, caster.internal.world, {1.0, 0.0, 0.0})
      spell = %{spell | id: 15_958}
      casting = caster |> Casting.start(spell, Target.self(caster.object.guid), 1_000) |> Casting.complete(1_000)
      assert [%Effects.CheckCastRequirements{cast: cast}] = casting.internal.events
      stop_supervised!(guid)
      failed = Casting.resolve_requirements(casting, cast, SpellRequirements.resolve(caster, spell), 1_000)
      assert failed.internal.casting == nil
      assert failed.unit.power1 == 100
      assert failed.internal.cooldowns == %{}
      refute Enum.any?(failed.internal.events, &match?(%Effects.SpellGameObjectAction{}, &1))
    end

    test "projects object hits and delivers only the matching actions", %{caster: caster, spell: spell} do
      guid = spawn_object(100, caster.internal.world, {1.0, 0.0, 0.0})
      casting = caster |> Casting.start(spell, Target.self(caster.object.guid), 1_000) |> Casting.complete(1_000)
      assert [%Effects.CheckCastRequirements{cast: cast}] = casting.internal.events
      completed = Casting.resolve_requirements(casting, cast, SpellRequirements.resolve(caster, spell), 1_000)
      assert completed.unit.power1 == 90
      assert Enum.any?(completed.internal.events, &match?(%Effects.SpellGo{hit_guids: [^guid]}, &1))

      assert Enum.any?(
               completed.internal.events,
               &match?(%Effects.SpellGameObjectAction{target_guid: ^guid, action: 7}, &1)
             )

      EventSink.emit_pending(completed, Context.new(self()))
      assert :sys.get_state(Entity.pid(guid)).game_object.flags == 2
      assert Metadata.get(guid).go_lock_override
    end
  end

  defp caster(_context) do
    caster = %Character{
      object: %Object{guid: Guid.from_low_guid(:player, System.unique_integer([:positive]) + 82_000_000)},
      unit: %Unit{health: 100, max_health: 100, power1: 100, max_power1: 100, level: 60},
      player: %Player{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: WorldRef.instance(999, 501)}
    }

    World.update_position(caster)

    on_exit(fn ->
      World.remove_position(caster)
      Metadata.delete(caster.object.guid)
    end)

    spell = %Spell{
      id: 100,
      range_yards: 10.0,
      mana_cost: 10,
      power_type: 0,
      effects: [%Effect{index: 0, type: :activate_object, implicit_target_a: :game_object_near_caster, misc_value: 7}],
      object_targets: [%Selector{entry: 100}]
    }

    %{caster: caster, spell: spell}
  end

  defp spawn_object(entry, world, {x, y, z}) do
    template = %GameObjectTemplate{entry: entry, type: 0, size: 1.0, flags: 0, display_id: 1, faction: 0}
    object = GameObject.build_summoned(template, world, {x, y, z, 0.0})
    start_supervised!({ObjectServer, object}, id: object.object.guid)
    object.object.guid
  end
end
