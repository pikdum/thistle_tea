defmodule ThistleTea.Game.World.Entity.GameObjectSpellCastTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Combat.Engagement
  alias ThistleTea.Game.Core.Combat.Hostility
  alias ThistleTea.Game.Core.Condition
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.GameObject
  alias ThistleTea.Game.Core.Entity.GameObjectTemplate
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.ObjectTargets
  alias ThistleTea.Game.Core.Spell.SpellEffect
  alias ThistleTea.Game.Core.Spell.UnitTargets.Selector
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.GameObject.Goober
  alias ThistleTea.Game.World.Entity.GameObject.SpellCast
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata

  setup [:object]

  describe "launch/4" do
    test "retains different recipients and applies only their effects", %{object: object, spell: spell} do
      first = mob(object, 100, 2.0)
      second = mob(object, 200, 3.0)

      spell = %{
        spell
        | effects: [hd(spell.effects), %{hd(spell.effects) | index: 1, base_points: 19}],
          unit_targets: [%Selector{entry: 100, inverse_effect_mask: 2}, %Selector{entry: 200, inverse_effect_mask: 1}]
      }

      cast = SpellCast.launch(object, spell, second.object.guid)
      deliveries = deliveries(cast)
      assert Enum.map(deliveries, & &1.target_guid) == [first.object.guid, second.object.guid]

      for {{recipient, index, health}, delivery} <- Enum.zip([{first, 0, 29}, {second, 1, 39}], deliveries) do
        assert delivery.cast_context.effect_indices == [index]
        assert delivery.cast_context.caster_guid == object.object.guid
        {updated, _events} = SpellEffect.receive(recipient, delivery.cast_context, spell, 1_000)
        assert updated.unit.health == health
      end
    end

    test "evaluates conditions against the actual object source", %{object: object, spell: spell} do
      target = mob(object, 100, 2.0)
      condition = %Condition{entry: 900_071, type: :source_entry, value1: object.object.entry}
      spell = %{spell | unit_targets: [%Selector{entry: 100, condition: condition}]}
      assert [%Effects.DeliverSpell{target_guid: guid}] = deliveries(SpellCast.launch(object, spell, nil))
      assert guid == target.object.guid
      condition = %{condition | value1: object.object.entry + 1}
      spell = %{spell | unit_targets: [%Selector{entry: 100, condition: condition}]}
      assert SpellCast.launch(object, spell, target.object.guid).internal.events == []
    end

    test "does not substitute an activating player for a missing creature", %{object: object, spell: spell} do
      user = player(object, 1.0)
      assert SpellCast.launch(object, spell, user.object.guid).internal.events == []
      other = %{object | internal: %{object.internal | world: WorldRef.instance(999, 872)}}
      mob(other, 100, 1.0)
      assert SpellCast.launch(object, spell, user.object.guid).internal.events == []
      mob(object, 100, 20.0)
      assert SpellCast.launch(object, spell, user.object.guid).internal.events == []
    end

    test "source and destination areas include units without treating the object as a unit", context do
      %{object: object, spell: spell} = context
      user = player(object, 1.0)
      creature = mob(object, 100, 2.0)
      mob(object, 200, 20.0)

      for mode <- [:script_units_at_source, :script_units_at_destination] do
        spell = %{spell | unit_targets: [], effects: [%{hd(spell.effects) | implicit_target_a: mode}]}
        guids = object |> SpellCast.launch(spell, user.object.guid) |> deliveries() |> Enum.map(& &1.target_guid)
        assert Enum.sort(guids) == Enum.sort([user.object.guid, creature.object.guid])
      end
    end

    test "retains scripted destination coordinates in launch and delivery", %{object: object, spell: spell} do
      target = mob(object, 100, 4.0)
      spell = %{spell | effects: [%{hd(spell.effects) | implicit_target_a: :script_location_near_caster}]}
      cast = SpellCast.launch(object, spell, nil)
      assert [%Effects.DeliverSpell{target_guid: guid, cast_context: context}] = deliveries(cast)
      assert guid == target.object.guid
      assert context.destination_position == {4.0, 0.0, 0.0}
      assert context.caster_position == {object.internal.world, 0.0, 0.0, 0.0}
      assert context.effect_indices == [0]
      launch = Enum.find(cast.internal.events, &is_struct(&1, Effects.SpellGo))
      assert launch.targets.destination_location == {4.0, 0.0, 0.0}
    end

    test "owned casts keep owner attribution and object geometry", %{object: object, spell: spell} do
      owner = player(object, 100.0)
      object = %{object | game_object: %{object.game_object | created_by: owner.object.guid}}
      near = mob(object, 100, 2.0)
      mob(object, 100, 101.0)
      cast = SpellCast.launch(object, spell, nil, caster_guid: owner.object.guid, level: 42)
      assert [%Effects.DeliverSpell{cast_context: context, target_guid: guid}] = deliveries(cast)
      assert guid == near.object.guid
      assert context.caster_guid == owner.object.guid
      assert context.caster_owner_guid == owner.object.guid
      assert context.caster_level == 42
      assert context.caster_position == {object.internal.world, 0.0, 0.0, 0.0}
    end

    test "owned object hostility follows the owner instead of the template", %{object: object} do
      owner = player(object, 100.0)
      faction = %FactionTemplate{id: 1, faction: 1, faction_group: 1, friend_group: 1, enemy_group: 2}
      Metadata.update(owner.object.guid, %{faction_template: faction})
      object = %{object | game_object: %{object.game_object | created_by: owner.object.guid}}
      assert Hostility.faction_template(object) == faction
      assert Hostility.friendly?(object, owner)
      refute Hostility.valid_attack_target?(object, owner)
    end

    test "object actions retain object hits without a unit delivery", %{object: object, spell: spell} do
      template = %GameObjectTemplate{entry: 900_073, type: 0, size: 1.0, flags: 0}
      target = GameObject.build_summoned(template, object.internal.world, {3.0, 0.0, 0.0, 0.0})
      {:ok, _pid} = World.start_entity(target)
      on_exit(fn -> World.stop_entity(target.object.guid) end)

      spell = %{
        spell
        | unit_targets: [],
          object_targets: [%ObjectTargets.Selector{entry: template.entry}],
          effects: [
            %Effect{index: 0, type: :activate_object, implicit_target_a: :game_object_near_caster, misc_value: 1}
          ]
      }

      cast = SpellCast.launch(object, spell, nil)
      assert deliveries(cast) == []
      launch = Enum.find(cast.internal.events, &is_struct(&1, Effects.SpellGo))
      assert launch.hit_guids == [target.object.guid]

      assert Enum.any?(
               cast.internal.events,
               &match?(%Effects.SpellGameObjectAction{target_guid: guid} when guid == target.object.guid, &1)
             )
    end

    test "object damage retains health loss without creating an object combat opponent", context do
      %{object: object, spell: spell} = context
      target = mob(object, 100, 3.0)
      spell = %{spell | school: :physical, effects: [%{hd(spell.effects) | type: :school_damage}]}
      [delivery] = deliveries(SpellCast.launch(object, spell, nil))

      {damaged, _events} = SpellEffect.receive(target, delivery.cast_context, spell, 1_000)
      assert damaged.unit.health == 11
      refute damaged.internal.in_combat
      refute Map.has_key?(damaged.internal.threat || %{}, object.object.guid)
      refute Enum.any?(damaged.internal.events, &is_struct(&1, Effects.AttackerGained))

      owner = player(object, 5.0)
      %Engagement.Result{entity: engaged} = Engagement.enter(target, owner.object.guid, 1_000)
      {damaged, _events} = SpellEffect.receive(engaged, delivery.cast_context, spell, 2_000)
      assert damaged.unit.health == 11
      assert damaged.internal.in_combat
      assert damaged.unit.target == owner.object.guid
      assert Map.keys(damaged.internal.threat) == [owner.object.guid]

      {damaged_player, _events} = SpellEffect.receive(owner, delivery.cast_context, spell, 1_000)
      assert damaged_player.unit.health == 11
      refute damaged_player.internal.in_combat
    end
  end

  describe "trap activation" do
    test "delivers to a scripted creature once and cleans up an exhausted trap", %{object: object, spell: spell} do
      key = {:spell, spell.id}
      previous = :ets.lookup(SpellLoader, key)
      :ets.insert(SpellLoader, {key, spell})

      on_exit(fn ->
        :ets.delete(SpellLoader, key)
        :ets.insert(SpellLoader, previous)
      end)

      user = player(object, 1.0)
      target = mob(object, 100, 3.0)
      template = %GameObjectTemplate{entry: 900_072, type: 6, size: 1.0, flags: 0, data: [0, 42, 0, spell.id, 1]}
      trap = GameObject.build_summoned(template, object.internal.world, object.movement_block.position)
      {:ok, pid} = World.start_entity(trap)
      monitor = Process.monitor(pid)
      on_exit(fn -> World.stop_entity(trap.object.guid) end)
      send(pid, {:script_activate_object, user.object.guid})
      send(pid, {:script_activate_object, user.object.guid})

      assert_receive {:"$gen_cast", {:receive_spell, context, ^spell}}, 1_000
      assert context.target_guid == target.object.guid
      assert context.caster_guid == trap.object.guid
      assert context.caster_level == 42
      assert context.effect_indices == [0]
      assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 1_000
      refute_receive {:"$gen_cast", {:receive_spell, _, ^spell}}
      assert World.position(trap.object.guid) == nil
      assert Metadata.get(trap.object.guid) == nil
    end
  end

  describe "finish_spell/3" do
    test "quest objects resolve nearby creatures instead of the user", %{object: object, spell: spell} do
      user = player(object, 1.0)
      target = mob(object, 100, 3.0)

      assert [%Effects.DeliverSpell{target_guid: guid}] =
               deliveries(Goober.finish_spell(object, spell, user.object.guid))

      assert guid == target.object.guid
      World.remove_position(user)
      assert Goober.finish_spell(object, spell, user.object.guid).internal.events == []
    end
  end

  defp object(_context) do
    world = WorldRef.instance(999, 871)
    template = %GameObjectTemplate{entry: 900_071, type: 10, size: 1.0, flags: 0, faction: 0}
    object = GameObject.build_summoned(template, world, {0.0, 0.0, 0.0, 0.0})

    spell = %Spell{
      id: 900_071,
      range_yards: 10.0,
      attributes: MapSet.new([:ignore_line_of_sight]),
      effects: [%Effect{index: 0, type: :heal, base_points: 9, implicit_target_a: :creature_near_caster}],
      unit_targets: [%Selector{entry: 100}]
    }

    %{object: object, spell: spell}
  end

  defp mob(object, entry, x) do
    guid = Guid.from_low_guid(:unit, entry, rem(System.unique_integer([:positive]), 1_000_000) + 8_000_000)

    publish(%Mob{
      object: %Object{guid: guid, entry: entry},
      unit: %Unit{health: 20, max_health: 100, level: 60, combat_reach: 0.0},
      internal: %Internal{world: object.internal.world},
      movement_block: %MovementBlock{position: {x, 0.0, 0.0, 0.0}}
    })
  end

  defp player(object, x) do
    publish(%Character{
      object: %Object{guid: Guid.from_low_guid(:player, System.unique_integer([:positive]) + 87_000_000)},
      unit: %Unit{health: 20, max_health: 100, level: 60},
      internal: %Internal{world: object.internal.world},
      movement_block: %MovementBlock{position: {x, 0.0, 0.0, 0.0}}
    })
  end

  defp publish(entity) do
    guid = entity.object.guid
    Entity.register(guid)
    World.update_position(entity)
    Metadata.put(guid, %{entry: entity.object.entry, alive?: true, level: 60, combat_reach: 0.0})

    on_exit(fn ->
      World.remove_position(entity)
      Metadata.delete(guid)
    end)

    entity
  end

  defp deliveries(object), do: Enum.filter(object.internal.events, &is_struct(&1, Effects.DeliverSpell))
end
