defmodule ThistleTea.Game.Entity.Logic.DistancingTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.CreatureSpell
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Entity.Logic.AI.BT.Distancing
  alias ThistleTea.Game.Entity.Logic.AI.BT.Mob.Spells
  alias ThistleTea.Game.Entity.Logic.AI.NavigationIntent
  alias ThistleTea.Game.Entity.Logic.AI.Script
  alias ThistleTea.Game.Entity.Logic.Assistance
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Engagement
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Entity.Server.DistancingNavigation
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.World.Loader.Script, as: ScriptLoader
  alias ThistleTea.Game.WorldRef

  setup [:mob]

  describe "Script.run/5" do
    @tag :vmangos_db
    test "loads caster distancing with its mana threshold", %{mob: mob} do
      scripts = ScriptLoader.load_by_ids(Mangos.CreatureAiScript, [59_901, 9_503])
      assert [%ScriptStep{command: :movement, datalong: 19, datalong3: 20} = step] = scripts[59_901]
      assert elem(step.position, 0) == 12.0
      assert [%ScriptStep{command: :movement, datalong: 19, datalong3: 0}] = scripts[9_503]
      context = %{context(0) | script_conditions: %{2428 => :met}}

      for {mana, expected?} <- [{19, false}, {20, true}, {100, true}] do
        entity = %{mob | unit: %{mob.unit | power1: mana, max_power1: 100}}
        {entity, _} = Script.run(entity, entity.internal.blackboard, [step], 2, context)
        assert Distancing.active?(entity) == expected?
      end
    end

    test "includes target size and leaves combat ownership untouched", %{mob: mob} do
      requested = request(mob)
      assert requested.internal.blackboard.distancing.destination == {9.5, 0.0, 0.0}
      assert requested.unit.target == 2
      assert requested.internal.threat == mob.internal.threat
      assert requested.internal.in_combat
      refute Blackboard.fleeing?(requested.internal.blackboard)
      assert requested.internal.events == []
    end

    test "rejects dead, missing, foreign-world and self targets", %{mob: mob} do
      for target <- [nil, 1, 99] do
        {entity, _} = Distancing.start(mob, mob.internal.blackboard, target, 12.0, context(0))
        refute Distancing.active?(entity)
      end

      for observation <- [
            put_in(context(0).perception.entities[2].metadata.alive?, false),
            put_in(context(0).perception.entities[2].position, {WorldRef.instance(0, 5), -3.0, 0.0, 0.0})
          ] do
        refute Distancing.active?(request(mob, observation))
      end
    end
  end

  describe "DistancingNavigation.resolve/5" do
    test "checks target line of sight and ground height before interrupting a cast", %{mob: mob} do
      entity = %{mob | internal: %{mob.internal | casting: cast(1)}}

      visible = fn map, from, to ->
        assert map == 0
        assert from == {-3.0, 0.0, 0.0}
        assert to == {9.5, 0.0, 1.0}
        true
      end

      find_path = fn map, from, to, opts ->
        assert map == 0
        assert from == {0.0, 0.0, 0.0}
        assert to == {9.5, 0.0, 1.0}
        assert opts[:allow_steep]
        [to]
      end

      result =
        resolve(request(entity), find_path, snap_to_ground: fn _, {x, y, _} -> {x, y, 1.0} end, line_of_sight?: visible)

      assert result.internal.casting == nil
      assert Enum.any?(result.internal.events, &is_struct(&1, Effects.SpellCastFailed))
      assert Movement.moving?(result, 0)
      assert Bitwise.band(result.movement_block.spline_flags, 0x100) != 0
      assert Bitwise.band(result.movement_block.movement_flags, 0x100) == 0
      refute result.internal.running
    end

    test "failed geometry and paths preserve the current cast and movement", %{mob: mob} do
      original = %{mob | internal: %{mob.internal | casting: cast(1)}}
      original = Movement.move_along_path(original, [{0.0, 20.0, 0.0}], [run?: false], 0)

      for {find_path, geometry} <- [
            {fn _, _, _, _ -> nil end, []},
            {fn _, _, _, _ -> [] end, []},
            {fn _, _, _, _ -> [{2.0, 0.0, 0.0}] end, []},
            {&direct_path/4, [line_of_sight?: fn _, _, _ -> false end]},
            {&direct_path/4, [snap_to_ground: fn _, {x, y, _} -> {x, y, 11.0} end]}
          ] do
        result = resolve(request(original), find_path, geometry)
        refute Distancing.active?(result)
        assert result.internal.casting == original.internal.casting
        assert result.movement_block == original.movement_block
        assert result.internal.events == original.internal.events
      end
    end

    test "preserves casts which do not interrupt on movement", %{mob: mob} do
      mob = %{mob | internal: %{mob.internal | casting: cast(8)}}
      assert resolve(request(mob)).internal.casting == mob.internal.casting
    end
  end

  describe "tick/3" do
    test "finishes at the requested distance and releases the spell-list deadline", %{mob: mob} do
      mob = put_in(mob.internal.blackboard.spells.next_list_at, 9_000)
      moving = resolve(request(mob))
      assert {{:running, _, :distancing}, moving} = tick(moving, 500)
      arrived = Movement.sync_position(moving, 2_000)
      assert {:failure, arrived} = tick(arrived, 2_000)
      assert arrived.movement_block.position == {9.5, 0.0, 0.0, 0.0}
      assert arrived.internal.blackboard.spells.next_list_at == 0
      refute Distancing.active?(arrived)
      assert Spells.flags_allow?(arrived, %CreatureSpell{}, 2, context(2_000))
    end

    test "blocks normal casts during retreat while allowing forced casts", %{mob: mob} do
      moving = resolve(request(mob))
      refute Spells.flags_allow?(moving, %CreatureSpell{}, 2, context(500))
      assert Spells.flags_allow?(moving, %CreatureSpell{cast_flags: MapSet.new([:force_cast])}, 2, context(500))
    end

    test "continues after a speed change replaces the spline", %{mob: mob} do
      moving = resolve(request(mob))
      slower = %{moving | movement_block: %{moving.movement_block | run_speed: 3.5}}
      {slower, _} = Movement.retime(slower, :run_speed, 500)
      refute slower.internal.spline_id == moving.internal.spline_id
      assert Distancing.active?(Distancing.maintain(slower, context(500)))
      assert {{:running, _, :distancing}, _} = tick(slower, 500)
    end
  end

  describe "maintain/2" do
    test "root, stun, fear and victim loss cancel rather than resume retreat", %{mob: mob} do
      moving = resolve(request(mob))

      for entity <- [
            %{moving | internal: %{moving.internal | rooted?: true}},
            %{moving | unit: %{moving.unit | target: 3}},
            %{moving | internal: %{moving.internal | in_combat: false}},
            aura(moving, :mod_stun),
            aura(moving, :mod_fear),
            aura(moving, :mod_confuse)
          ] do
        result = Distancing.maintain(entity, context(500))
        refute Distancing.active?(result)
        refute Movement.moving?(result, 500)
      end

      result = Distancing.maintain(moving, Context.new(500))
      refute Distancing.active?(result)
      refute Movement.moving?(result, 500)
    end

    test "a replacement path survives cancellation of the old retreat", %{mob: mob} do
      replaced = mob |> request() |> resolve() |> Movement.move_along_path([{0.0, 20.0, 0.0}], [run?: false], 500)
      result = Distancing.maintain(replaced, context(500))
      refute Distancing.active?(result)
      assert result.movement_block == replaced.movement_block
      assert Movement.moving?(result, 500)
    end

    test "can cancel an unresolved request without an active spline", %{mob: mob} do
      result = mob |> request() |> Distancing.maintain(Context.new(0))
      refute Distancing.active?(result)
      assert result.internal.events == []
    end

    test "death and combat exit clear distancing", %{mob: mob} do
      moving = resolve(request(mob))
      %{entity: left} = Engagement.leave(moving, :evade)
      dead = Core.kill(moving, 500)
      refute Distancing.active?(left)
      refute Distancing.active?(dead)
      refute Movement.moving?(dead, 500)
    end
  end

  describe "Assistance.flee_from_help/4" do
    test "retreats from a nearby enemy without joining combat", %{mob: mob} do
      idle = idle(mob)
      result = Assistance.flee_from_help(idle, 3, 2, context(0))
      assert Distancing.active?(result)
      assert result.internal.blackboard.distancing.destination == {7.5, 0.0, 0.0}
      assert result.unit.target == 0
      assert result.internal.threat == %{}
      refute result.internal.in_combat
    end

    test "requires wandering and rechecks roots, distance and faction", %{mob: mob} do
      idle = idle(mob)

      for entity <- [
            mob,
            %{idle | internal: %{idle.internal | rooted?: true}},
            put_in(idle.internal.spawn.movement_type, 0),
            put_in(idle.internal.blackboard.navigation.movement_override, :waypoint)
          ] do
        refute Distancing.active?(Assistance.flee_from_help(entity, 3, 2, context(0)))
      end

      for observation <- [
            put_in(context(0).perception.entities[2].position, {WorldRef.open(0), -11.0, 0.0, 0.0}),
            put_in(context(0).perception.entities[1].metadata.faction_template.flags, 1),
            put_in(context(0).perception.entities[1].metadata.flee_from_help_available?, false)
          ] do
        refute Distancing.active?(Assistance.flee_from_help(idle, 3, 2, observation))
      end
    end

    test "passive creatures and critters may retreat even when they cannot assist", %{mob: mob} do
      idle = idle(mob)

      idle = %{
        idle
        | unit: %{idle.unit | flags: 0x20000},
          internal: %{idle.internal | creature: %Creature{critter?: true, extra_flags: 0x10000}}
      }

      refute Assistance.available?(idle)
      assert Assistance.flee_available?(idle)
      assert Distancing.active?(Assistance.flee_from_help(idle, 3, 2, context(0)))
    end
  end

  defp mob(_context) do
    %{
      mob: %Mob{
        object: %Object{guid: 1},
        unit: %Unit{health: 100, max_health: 100, level: 50, flags: 0, auras: [], target: 2},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, walk_speed: 2.5, run_speed: 7.0},
        internal: %Internal{
          world: WorldRef.open(0),
          running: false,
          in_combat: true,
          creature: %Creature{},
          blackboard: Blackboard.new(),
          threat: %{2 => 20.0}
        }
      }
    }
  end

  defp idle(mob),
    do: %{
      mob
      | unit: %{mob.unit | target: 0},
        internal: %{mob.internal | in_combat: false, threat: %{}, spawn: %Spawn{movement_type: 1}}
    }

  defp context(now) do
    faction = %FactionTemplate{id: 36, flags: 0x401, faction_group: 8, enemy_group: 1}

    entities = %{
      1 => %Observation{
        guid: 1,
        position: {WorldRef.open(0), 0.0, 0.0, 0.0},
        metadata: %{flee_from_help_available?: true, faction_template: faction}
      },
      2 => %Observation{
        guid: 2,
        position: {WorldRef.open(0), -3.0, 0.0, 0.0},
        metadata: %{alive?: true, bounding_radius: 0.5, faction_template: %FactionTemplate{id: 1, faction_group: 1}}
      },
      3 => %Observation{
        guid: 3,
        position: {WorldRef.open(0), 2.0, 0.0, 0.0},
        metadata: %{alive?: true, faction_template: faction}
      }
    }

    Context.new(now, perception: Perception.new(now, nil, entities, %{}))
  end

  defp request(mob, context \\ context(0)) do
    {mob, _} =
      Script.run(
        mob,
        mob.internal.blackboard,
        [%ScriptStep{command: :movement, datalong: 19, position: {12.0, 0.0, 0.0, 0.0}}],
        2,
        context
      )

    mob
  end

  defp resolve(mob, find_path \\ &direct_path/4, geometry \\ []) do
    {mob, [intent]} = NavigationIntent.drain(mob)
    defaults = [snap_to_ground: fn _, point -> point end, line_of_sight?: fn _, _, _ -> true end]
    DistancingNavigation.resolve(mob, intent, 0, find_path, Keyword.merge(defaults, geometry))
  end

  defp direct_path(_map, _from, to, _opts), do: [to]
  defp tick(mob, now), do: BT.tick(BT.action(&Distancing.tick/3), mob, context(now))
  defp cast(flags), do: Cast.new(%Spell{id: 7, interrupt_flags: flags, cast_time_ms: 5_000}, Target.unit(2), 0)

  defp aura(mob, type) do
    spell = %Spell{
      id: 99,
      duration_ms: 10_000,
      effects: [%Effect{index: 0, type: :apply_aura, aura: type, implicit_target_a: :target_enemy}]
    }

    {mob, _} = Aura.apply_spell(mob, 2, 50, spell, 500)
    mob
  end
end
