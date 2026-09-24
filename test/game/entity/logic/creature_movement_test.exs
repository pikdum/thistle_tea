defmodule ThistleTea.Game.Entity.Logic.CreatureMovementTest do
  use ExUnit.Case, async: true

  import Bitwise, only: [&&&: 2, |||: 2]

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.Internal.WaypointRoute
  alias ThistleTea.Game.Entity.Data.CreatureArchetype
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BehaviorRunner
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Mob, as: MobBT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Patrol
  alias ThistleTea.Game.Entity.Logic.AI.NavigationIntent
  alias ThistleTea.Game.Entity.Logic.CreatureEntry
  alias ThistleTea.Game.Entity.Logic.CreatureMovement
  alias ThistleTea.Game.Entity.Logic.Falling
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Entity.Server.Mob.Flight
  alias ThistleTea.Game.Entity.Server.NavigationResolver
  alias ThistleTea.Game.Network.Message.SmsgMonsterMove

  setup [:build_flyer]

  describe "path_options/1" do
    test "separates water permission from swim animation" do
      fish = build_mob(2)
      fish = %{fish | internal: %{fish.internal | creature: %{fish.internal.creature | static_flags: 0x10000000}}}

      refute CreatureMovement.can_walk?(fish)
      assert CreatureMovement.can_swim?(fish)
      assert CreatureMovement.swims?(fish)
      assert CreatureMovement.accessible?(fish, true)
      refute CreatureMovement.accessible?(fish, false)

      bottom_walker = build_mob(3)
      assert CreatureMovement.can_walk?(bottom_walker)
      assert CreatureMovement.can_swim?(bottom_walker)
      refute CreatureMovement.swims?(bottom_walker)

      land = build_mob(1)
      assert CreatureMovement.accessible?(land, false)
      refute CreatureMovement.accessible?(land, true)
    end

    test "combat pets can travel between habitats while charmed creatures retain their restrictions" do
      fish = build_mob(2)

      for kind <- [:hunter, :summon] do
        pet = %{fish | internal: %{fish.internal | pet: %Pet{kind: kind}}}
        assert CreatureMovement.can_walk?(pet)
        assert CreatureMovement.can_swim?(pet)
      end

      charmed = %{fish | internal: %{fish.internal | pet: %Pet{kind: :charmed}}}
      refute CreatureMovement.can_walk?(charmed)
      assert CreatureMovement.can_swim?(charmed)
    end
  end

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
    test "passes aquatic capabilities to the path boundary without enabling flight" do
      fish = build_mob(2)
      fish = %{fish | internal: %{fish.internal | creature: %{fish.internal.creature | static_flags: 0x10000000}}}
      requested = NavigationIntent.enqueue(fish, {20.0, 0.0, 35.0}, run?: true)

      moving =
        NavigationResolver.resolve(requested, 0, fn 0, _, destination, opts ->
          assert opts[:can_swim?]
          refute opts[:can_walk?]
          assert opts[:swim_animation?]
          assert opts[:minimum_depth] > 0
          refute opts[:flying?]
          [destination]
        end)

      assert moving.movement_block.spline_nodes == [{20.0, 0.0, 35.0}]
      assert (moving.movement_block.spline_flags &&& 0x200) == 0
    end

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

  describe "cycle/5" do
    test "loads and repeats the entire authored route without per-point stops", %{mob: mob} do
      route = cyclic_route()
      assert route.cyclic?
      mob = %{mob | internal: %{mob.internal | spawn: %{mob.internal.spawn | waypoint_route: route, movement_type: 3}}}
      blackboard = Blackboard.put_next_at(Blackboard.new(), :next_aggro_at, 100_000, 0)
      mob = BT.init(mob, MobBT.tree(), blackboard)
      assert {{:running, 0, :navigation}, requested} = BehaviorRunner.tick(MobBT.tree(), mob, Context.new(0))
      assert [%NavigationIntent{path: path}] = requested.internal.navigation_intents
      assert path == [{0.0, 0.0, 30.0}, {10.0, 10.0, 35.0}, {-10.0, 10.0, 40.0}, {0.0, 0.0, 30.0}]
      moving = NavigationResolver.resolve(requested, 0, fn _, _, _, _ -> flunk("authored route queried ground") end)
      assert moving.movement_block.spline_nodes == path
      deadline = moving.movement_block.duration
      arrived = Movement.sync_position(moving, deadline)
      assert {{:running, 0, :navigation}, repeated} = BehaviorRunner.tick(MobBT.tree(), arrived, Context.new(deadline))
      assert [%NavigationIntent{path: ^path}] = repeated.internal.navigation_intents
    end

    test "approaches the first node through navigation after an interruption", %{mob: mob} do
      mob = %{mob | movement_block: %{mob.movement_block | position: {30.0, 0.0, 30.0, 0.0}}}

      assert {{:running, 1_000, :navigation}, requested, blackboard} =
               Patrol.cycle(mob, Blackboard.new(), Context.new(0), cyclic_route(), [])

      assert [%NavigationIntent{destination: {+0.0, +0.0, 30.0}, path: nil}] = requested.internal.navigation_intents
      assert blackboard.navigation.move_target == {0.0, 0.0, 30.0}
    end

    test "roots block both cyclic routes and idle flight circles", %{mob: mob} do
      mob = %{mob | movement_block: %{mob.movement_block | movement_flags: 0x08000000}}

      assert {{:running, 1_000, :blocked}, ^mob, _} =
               Patrol.cycle(mob, Blackboard.new(), Context.new(0), cyclic_route(), [])

      assert {{:running, 1_000, :blocked}, ^mob, _} =
               Patrol.circle(mob, Blackboard.new(), Context.new(0), {0.0, 0.0, 30.0}, 10.0, [])
    end

    test "combat interrupts circles at their current position", %{mob: mob} do
      {_, requested, blackboard} = Patrol.circle(mob, Blackboard.new(), Context.new(0), {0.0, 0.0, 30.0}, 10.0, [])
      moving = NavigationResolver.resolve(requested, 0)
      {:success, stopped, blackboard} = MobBT.interrupt_idle_movement(moving, blackboard, 1_000)
      refute Movement.moving?(stopped, 1_000)
      assert stopped.movement_block.position != moving.movement_block.position
      assert blackboard.navigation.move_target == nil
      assert CreatureMovement.flying?(stopped)
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

  defp cyclic_route do
    points = [{0.0, 0.0, 30.0}, {10.0, 10.0, 35.0}, {-10.0, 10.0, 40.0}]

    rows =
      points
      |> Enum.with_index()
      |> Enum.map(fn {{x, y, z}, index} ->
        %Mangos.CreatureMovement{
          point: index,
          position_x: x,
          position_y: y,
          position_z: z,
          orientation: 100.0,
          waittime: 0
        }
      end)

    WaypointRoute.build(%Mangos.Creature{movement_type: 3, creature_movement: rows})
  end

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
