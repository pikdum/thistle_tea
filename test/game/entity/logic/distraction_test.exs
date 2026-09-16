defmodule ThistleTea.Game.Entity.Logic.DistractionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Mob, as: MobBT
  alias ThistleTea.Game.Entity.Logic.Distraction
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Engagement
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.WorldRef

  setup [:build_mob]

  describe "apply/4" do
    test "halts a moving creature at its current position and turns it", %{mob: mob} do
      mob = %{mob | internal: %{mob.internal | movement_start_time: 0, movement_start_position: {0.0, 0.0, 0.0}}}
      movement = %{mob.movement_block | duration: 10_000, spline_nodes: [{10.0, 0.0, 0.0}]}
      {mob, events} = Distraction.apply(%{mob | movement_block: movement}, {5.0, 10.0, 0.0}, 10_000, 5_000)

      assert {5.0, +0.0, +0.0, orientation} = mob.movement_block.position
      assert_in_delta orientation, :math.pi() / 2, 0.001
      assert mob.movement_block.spline_nodes == []
      assert mob.internal.blackboard.navigation.distracted_until == 15_000
      assert [%Effects.MovementStopped{}, %Effects.SetFacing{}] = events
      refute mob.internal.in_combat
    end

    test "ignores combat, dead targets, and absent destinations", %{mob: mob} do
      for target <- [%{mob | internal: %{mob.internal | in_combat: true}}, %{mob | unit: %{mob.unit | health: 0}}] do
        assert {^target, []} = Distraction.apply(target, {0.0, 5.0, 0.0}, 10_000, 1_000)
      end

      assert {^mob, []} = Distraction.apply(mob, nil, 10_000, 1_000)
    end

    test "ignores units that cannot react", %{mob: mob} do
      for type <- [:mod_stun, :mod_confuse, :mod_fear, :feign_death] do
        holder = %Holder{spell: %Spell{id: 1}, auras: [%Aura{type: type}]}
        mob = %{mob | unit: %{mob.unit | auras: [holder]}}
        assert {^mob, []} = Distraction.apply(mob, {0.0, 5.0, 0.0}, 10_000, 1_000)
      end
    end

    test "turns a player without imposing a movement pause", %{mob: mob} do
      player = %Character{
        object: mob.object,
        unit: mob.unit,
        internal: mob.internal,
        movement_block: mob.movement_block
      }

      {player, [%Effects.SetFacing{}]} = Distraction.apply(player, {0.0, 5.0, 0.0}, 10_000, 1_000)
      assert_in_delta elem(player.movement_block.position, 3), :math.pi() / 2, 0.001
      assert player.internal.blackboard.navigation.distracted_until == nil
    end
  end

  describe "tick/3" do
    test "holds the patrol until expiry and then resumes navigation", %{mob: mob} do
      navigation = %{mob.internal.blackboard.navigation | target: {10.0, 0.0, 0.0}}
      mob = %{mob | internal: %{mob.internal | blackboard: %{mob.internal.blackboard | navigation: navigation}}}
      {mob, _} = Distraction.apply(mob, {0.0, 5.0, 0.0}, 10_000, 1_000)

      assert {{:running, 500, :distracted}, mob} = BT.tick(MobBT.tree(), mob, Context.new(1_001))
      assert mob.internal.navigation_intents == []
      assert {{:running, 1, :distracted}, mob} = BT.tick(MobBT.tree(), mob, Context.new(10_999))
      {_status, mob} = BT.tick(MobBT.tree(), mob, Context.new(11_000))
      assert mob.internal.blackboard.navigation.distracted_until == nil
      assert [%{destination: {10.0, +0.0, +0.0}}] = mob.internal.navigation_intents
    end

    test "combat permanently cancels the pause", %{mob: mob} do
      {mob, _} = Distraction.apply(mob, {0.0, 5.0, 0.0}, 10_000, 1_000)
      assert %Engagement.Result{entity: mob} = Engagement.enter(mob, 99, 2_000)
      assert mob.internal.in_combat
      assert mob.internal.blackboard.navigation.distracted_until == nil
    end
  end

  describe "receive/4" do
    test "dispatches a ground distraction with the effect's duration", %{mob: mob} do
      effect = %Effect{
        type: :distract,
        base_points: 9,
        base_dice: 1,
        die_sides: 1,
        implicit_target_a: :aoe_enemy_at_dest
      }

      spell = %Spell{id: 1725, school: :physical, effects: [effect], attributes: MapSet.new([:no_threat])}
      context = %CastContext{caster_guid: 99, target_role: :other, destination_position: {0.0, 5.0, 0.0}}
      {mob, [%Effects.SetFacing{}]} = SpellEffect.receive(mob, context, spell, 1_000)
      assert mob.internal.blackboard.navigation.distracted_until == 11_000
      assert Spell.harmful?(spell)
      refute Spell.starts_combat?(spell)
    end
  end

  defp build_mob(_) do
    blackboard = %Blackboard{combat: %Blackboard.Combat{next_aggro_at: 20_000}}

    mob = %Mob{
      object: %Object{guid: 1},
      unit: %Unit{health: 100, max_health: 100, level: 10, flags: 0, target: 0, auras: []},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, spline_nodes: [], walk_speed: 2.5, run_speed: 7.0},
      internal: %Internal{
        world: WorldRef.open(0),
        blackboard: blackboard,
        spawn: %Spawn{movement_type: 1, distance: 5.0}
      }
    }

    %{mob: mob}
  end
end
