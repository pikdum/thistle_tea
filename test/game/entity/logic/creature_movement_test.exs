defmodule ThistleTea.Game.Entity.Logic.CreatureMovementTest do
  use ExUnit.Case, async: true

  import Bitwise, only: [&&&: 2, |||: 2]

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.CreatureArchetype
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BehaviorRunner
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Mob, as: MobBT
  alias ThistleTea.Game.Entity.Logic.AI.NavigationIntent
  alias ThistleTea.Game.Entity.Logic.CreatureEntry
  alias ThistleTea.Game.Entity.Logic.CreatureMovement
  alias ThistleTea.Game.Entity.Logic.Falling
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Entity.Server.Mob.Flight
  alias ThistleTea.Game.Entity.Server.NavigationResolver
  alias ThistleTea.Game.Network.Message.SmsgMonsterMove

  setup [:build_flyer]

  describe "can_fly?/1" do
    test "loads template capability while combat pets remain grounded", %{mob: mob} do
      assert CreatureMovement.can_fly?(mob)
      assert (mob.movement_block.movement_flags &&& 0x01800000) == 0x01800000

      for kind <- [:hunter, :summon] do
        pet = %{mob | internal: %{mob.internal | pet: %Pet{kind: kind}}}
        refute CreatureMovement.can_fly?(pet)
        assert (CreatureMovement.sync(pet).movement_block.movement_flags &&& 0x01800000) == 0
      end

      charmed = %{mob | internal: %{mob.internal | pet: %Pet{kind: :charmed}}}
      assert CreatureMovement.can_fly?(charmed)
      refute CreatureMovement.can_fly?(build_mob(3))
    end
  end

  describe "sync/1" do
    test "retains flight and independent flags at rest and restores flight on respawn", %{mob: mob} do
      mob = %{
        mob
        | movement_block: %{mob.movement_block | movement_flags: mob.movement_block.movement_flags ||| 0x40000000}
      }

      moving = Movement.move_along_path(mob, [{20.0, 0.0, 30.0}], [run?: true], 0)
      assert (moving.movement_block.spline_flags &&& 0x200) != 0

      for resting <- [Movement.stop(moving, 100), Movement.sync_position(moving, 100_000)] do
        assert (resting.movement_block.movement_flags &&& 0x41800000) == 0x41800000
        assert resting.movement_block.spline_nodes == []
      end

      dead = CreatureMovement.sync(%{mob | unit: %{mob.unit | health: 0}})
      assert (dead.movement_block.movement_flags &&& 0x01800000) == 0
      assert CreatureMovement.flying?(Mob.respawn(dead))
      assert (Mob.respawn(dead).movement_block.movement_flags &&& 0x01800000) == 0x01800000
    end

    test "entry changes reconcile flight and respawn restores the original template", %{mob: mob} do
      grounded = build_mob(3)
      grounded = %{grounded | object: %{grounded.object | entry: 20}}
      changed = CreatureEntry.apply(mob, CreatureArchetype.from_mob(grounded), 0)
      refute CreatureMovement.flying?(changed)
      assert (changed.movement_block.movement_flags &&& 0x01800000) == 0
      assert CreatureMovement.flying?(Mob.respawn(changed))
    end
  end

  describe "circle/3" do
    test "flies repeated level circles without ground navigation or idle pauses", %{mob: mob} do
      mob = %{mob | movement_block: %{mob.movement_block | position: {10.0, 0.0, 30.0, 0.0}}}
      blackboard = Blackboard.put_next_at(Blackboard.new(), :next_aggro_at, 100_000, 0)
      mob = BT.init(mob, MobBT.tree(), blackboard)
      assert {{:running, 0, :navigation}, requested} = BehaviorRunner.tick(MobBT.tree(), mob, Context.new(0))
      assert [%NavigationIntent{path: path}] = requested.internal.navigation_intents
      assert length(path) == 20

      for {x, y, z} <- path do
        assert_in_delta :math.sqrt(x * x + y * y), 10.0, 0.001
        assert z == 30.0
      end

      moving = NavigationResolver.resolve(requested, 0, fn _, _, _, _ -> flunk("ground query") end)
      assert length(moving.movement_block.spline_nodes) == 20
      assert_in_delta moving.movement_block.duration, 8_939, 2
      assert (SmsgMonsterMove.build(moving).spline_flags &&& 0x200) != 0
      deadline = moving.movement_block.duration
      arrived = Movement.sync_position(moving, deadline)
      assert {{:running, 0, :navigation}, repeated} = BehaviorRunner.tick(MobBT.tree(), arrived, Context.new(deadline))
      assert [%NavigationIntent{path: [_ | _]}] = repeated.internal.navigation_intents
      assert NavigationResolver.resolve(repeated, deadline).movement_block.duration > 8_000
    end
  end

  describe "resolve/3" do
    test "requests airborne navigation for chase and home movement", %{mob: mob} do
      requested = NavigationIntent.enqueue(mob, {20.0, 0.0, 45.0}, face_target: 9)

      moving =
        NavigationResolver.resolve(requested, 0, fn 0, {+0.0, +0.0, 30.0}, destination, opts ->
          assert opts[:flying?]
          [destination]
        end)

      assert moving.movement_block.spline_nodes == [{20.0, 0.0, 45.0}]
      assert (moving.movement_block.spline_flags &&& 0x200) != 0
    end
  end

  describe "land_corpse/3" do
    test "falls to the highest surface below the corpse with matching acceleration", %{mob: mob} do
      dead = %{mob | unit: %{mob.unit | health: 0}}
      falling = Flight.land_corpse(dead, 1_000, fn 0, {+0.0, +0.0} -> [45.0, 10.0, -5.0] end)
      assert falling.movement_block.spline_nodes == [{0.0, 0.0, 10.0}]
      assert falling.movement_block.duration == Falling.duration(20.0)
      assert Movement.completion_at(falling) == 1_000 + Falling.duration(20.0)
      assert Movement.falling?(falling)
      assert (falling.movement_block.movement_flags &&& 0x01800000) == 0
      assert SmsgMonsterMove.build(falling).spline_flags == 0x102
      halfway = Movement.sync_position(falling, 1_500)
      assert_in_delta elem(halfway.movement_block.position, 2), 27.58861184, 0.00001
      landed = Movement.sync_position(falling, Movement.completion_at(falling))
      assert landed.movement_block.position == {0.0, 0.0, 10.0, 0.0}
      refute Movement.falling?(landed)
      assert Movement.completion_at(landed) == nil
    end

    test "avoids upward falls and tolerates missing ground", %{mob: mob} do
      dead = %{mob | unit: %{mob.unit | health: 0}}

      for heights <- [[], [50.0], [30.0]] do
        landed = Flight.land_corpse(dead, 0, fn _, _ -> heights end)
        refute Movement.falling?(landed)
        assert landed.movement_block.position == dead.movement_block.position
      end
    end

    test "limits long falls to terminal velocity" do
      assert_in_delta Falling.distance(5_000) - Falling.distance(4_000), 60.148003, 0.00001
      duration = Falling.duration(500.0)
      assert_in_delta Falling.distance(duration), 500.0, 0.061
    end
  end

  defp build_flyer(_context), do: %{mob: build_mob(4)}

  defp build_mob(inhabit_type) do
    Mob.build(%Mangos.Creature{
      guid: 1,
      id: 6139,
      position_z: 30.0,
      movement_type: 1,
      wander_distance: 10.0,
      curhealth: 100,
      creature_movement: [],
      creature_template: %Mangos.CreatureTemplate{
        entry: 6139,
        name: "Flyer",
        inhabit_type: inhabit_type,
        speed_run: 1.0
      }
    })
  end
end
