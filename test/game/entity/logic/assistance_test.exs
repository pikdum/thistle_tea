defmodule ThistleTea.Game.Entity.Logic.AssistanceTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Entity.Logic.AI.BT.Flee
  alias ThistleTea.Game.Entity.Logic.AI.BT.SeekAssistance
  alias ThistleTea.Game.Entity.Logic.AI.Script
  alias ThistleTea.Game.Entity.Logic.Assistance
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Engagement
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Entity.Server.NavigationResolver
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.World.Loader.Script, as: ScriptLoader
  alias ThistleTea.Game.WorldRef

  setup [:mob]

  describe "available?/1" do
    test "excludes busy, controlled, invisible and disabled helpers", %{mob: mob} do
      idle = %{mob | internal: %{mob.internal | in_combat: false}}
      assert Assistance.available?(idle)

      unavailable = [
        mob,
        %{idle | unit: %{idle.unit | health: 0}},
        %{idle | unit: %{idle.unit | summoned_by: 9}},
        %{idle | unit: %{idle.unit | charmed_by: 9}},
        %{idle | internal: %{idle.internal | pet: %Pet{owner_guid: 9}}},
        %{idle | internal: %{idle.internal | creature: %Creature{extra_flags: 0x10000}}},
        put_in(idle.internal.blackboard.navigation.returning_home?, true),
        aura(idle, :mod_invisibility)
      ]

      for entity <- unavailable, do: refute(Assistance.available?(entity))

      for flag <- [0x2, 0x20000, 0x40000, 0x02000000] do
        refute Assistance.available?(%{idle | unit: %{idle.unit | flags: flag}})
      end
    end
  end

  describe "nearest/2" do
    test "chooses the closest visible same-faction ally in the same world", %{mob: mob} do
      context = context(0)
      assert Assistance.nearest(mob, context.perception) == {3, {21.0, 0.0, 0.0}}

      for observation <- [
            %{helper(3, 21.0) | line_of_sight?: false},
            %{helper(3, 21.0) | position: {WorldRef.instance(0, 4), 21.0, 0.0, 0.0}},
            put_in(helper(3, 21.0).metadata.assistance_available?, false),
            put_in(helper(3, 21.0).metadata.faction_template.id, 99)
          ] do
        perception = %{context.perception | entities: Map.put(context.perception.entities, 3, observation)}
        assert Assistance.nearest(mob, perception) == {4, {28.0, 0.0, 0.0}}
      end
    end

    test "cannot select helpers beyond thirty yards", %{mob: mob} do
      perception = %{context(0).perception | nearby: %{mobs: [{3, 31.0}]}}
      assert Assistance.nearest(mob, perception) == nil
    end
  end

  describe "Script.run/5" do
    @tag :vmangos_db
    test "loads the Horde Laborer assistance command", %{mob: mob} do
      scripts = ScriptLoader.load_by_ids(Mangos.CreatureAiScript, [1_471_802])
      assert [%ScriptStep{command: :flee, datalong: 1}] = steps = scripts[1_471_802]
      {_, blackboard} = Script.run(mob, mob.internal.blackboard, steps, 2, context(0))
      assert blackboard.assistance.helper_guid == 3
    end

    test "seeks an ally without losing the authoritative victim", %{mob: mob} do
      mob = start(mob)
      assert mob.internal.blackboard.assistance.helper_guid == 3
      assert mob.unit.target == 2
      assert Core.update_object(mob).unit.target == 0
      assert Core.update_object(mob, :values).unit.target == 0
      assert [%Effects.MonsterTalk{chat_type: :text_emote}] = mob.internal.events
      assert Script.observation_radius([%ScriptStep{command: :flee, datalong: 1}]) == 30.0
    end

    test "falls back to timed panic when no helper is visible", %{mob: mob} do
      mob = start(mob, Context.new(0))
      assert mob.internal.blackboard.assistance == nil
      assert mob.internal.blackboard.combat.flee_until == 7_000
      assert Bitwise.band(mob.unit.flags, 0x00800000) != 0
    end

    test "suppresses fleeing under prevention, confusion, possession and distraction", %{mob: mob} do
      for entity <- [
            aura(mob, :prevent_fleeing),
            aura(mob, :mod_confuse),
            aura(mob, :feign_death),
            %{mob | internal: %{mob.internal | pet: %Pet{owner_guid: 9, possessed?: true}}},
            put_in(mob.internal.blackboard.navigation.distracted_until, 500)
          ] do
        result = start(entity)
        assert result.internal.blackboard.assistance == nil
        refute Blackboard.fleeing?(result.internal.blackboard)
        refute Enum.any?(result.internal.events, &is_struct(&1, Effects.MonsterTalk))
      end
    end

    test "interrupts only casts with movement interruption", %{mob: mob} do
      for {flags, interrupted?} <- [{1, true}, {8, false}] do
        cast = Cast.new(%Spell{id: 7, interrupt_flags: flags, cast_time_ms: 5_000}, Target.unit(2), 0)
        result = start(%{mob | internal: %{mob.internal | casting: cast}})
        assert is_nil(result.internal.casting) == interrupted?
      end
    end
  end

  describe "tick/3" do
    test "walks at fleeing speed, calls once on arrival and resumes after the delay", %{mob: mob} do
      moving = moving(mob)
      assert moving.movement_block.duration == 3_000
      assert moving.internal.movement_speed == {:run_speed, 7.0}
      assert Bitwise.band(moving.movement_block.spline_flags, 0x100) == 0
      assert Bitwise.band(moving.movement_block.movement_flags, 0x100) != 0

      arrived = Movement.sync_position(moving, 3_001)
      assert {{:running, 1_500, :assistance}, waiting} = tick(arrived, 3_001)
      assert waiting.movement_block.position == {21.0, 0.0, 0.0, 0.0}
      assert Enum.count(waiting.internal.events, &is_struct(&1, Effects.CallAssistance)) == 1
      assert {{:running, 1, :assistance}, waiting} = tick(waiting, 4_500)
      assert Enum.count(waiting.internal.events, &is_struct(&1, Effects.CallAssistance)) == 1
      assert {:failure, resumed} = tick(waiting, 4_501)
      assert resumed.internal.running
      assert resumed.internal.blackboard.assistance == nil
      assert Core.update_object(resumed).unit.target == 2
      assert resumed.internal.broadcast_update?
    end

    test "retimes the retreat after a running-speed change without changing gait", %{mob: mob} do
      moving = moving(mob)
      slower = %{moving | movement_block: %{moving.movement_block | run_speed: 3.5}}
      {slower, events} = Movement.retime(slower, :run_speed, 1_000)
      assert slower.movement_block.duration == 4_000
      assert Bitwise.band(slower.movement_block.spline_flags, 0x100) == 0
      assert Bitwise.band(slower.movement_block.movement_flags, 0x100) != 0
      assert Enum.any?(events, &is_struct(&1, Effects.MonsterMove))
    end

    test "root pauses the retreat and removal requests the remaining path", %{mob: mob} do
      moving = moving(mob)
      rooted = %{moving | internal: %{moving.internal | rooted?: true}}
      rooted = SeekAssistance.maintain(rooted, context(1_000))
      refute Movement.moving?(rooted, 1_000)
      refute rooted.internal.blackboard.assistance.requested?
      assert {{:running, 500, :assistance}, rooted} = tick(rooted, 1_000)
      unrooted = %{rooted | internal: %{rooted.internal | rooted?: false}}
      assert {{:running, 0, :navigation}, unrooted} = tick(unrooted, 2_000)
      assert [%{destination: destination}] = unrooted.internal.navigation_intents
      assert destination == {21.0, 0.0, 0.0}
      refute Enum.any?(unrooted.internal.events, &is_struct(&1, Effects.CallAssistance))
    end

    test "failed paths call from the actual position instead of retrying forever", %{mob: mob} do
      assert {{:running, 0, :navigation}, mob} = mob |> start() |> tick(0)
      mob = NavigationResolver.resolve(mob, 0, fn _, _, _, _ -> nil end)
      assert {{:running, 1_500, :assistance}, mob} = tick(mob, 1)
      assert mob.movement_block.position == {0.0, 0.0, 0.0, 0.0}
    end

    test "a changed or lost victim cancels the retreat", %{mob: mob} do
      moving = moving(mob)

      for {entity, perception} <- [
            {%{moving | unit: %{moving.unit | target: 5}}, context(500).perception},
            {moving, Perception.empty(500)},
            {moving, put_in(context(500).perception.entities[2].metadata.alive?, false).perception}
          ] do
        result = SeekAssistance.maintain(entity, Context.new(500, perception: perception))
        assert result.internal.blackboard.assistance == nil
        assert result.internal.running
        refute Movement.moving?(result, 500)
      end
    end

    test "fear cancels assistance and retains the original movement mode", %{mob: mob} do
      result = mob |> moving() |> aura(:mod_fear)
      result = SeekAssistance.maintain(result, context(500))
      assert result.internal.blackboard.assistance == nil
      assert result.internal.blackboard.fear.previous_running
    end

    test "combat end and death clear the retreat", %{mob: mob} do
      moving = moving(mob)
      %{entity: left} = Engagement.leave(moving, :evade)
      dead = Core.kill(moving, 500)

      for entity <- [left, dead] do
        assert entity.internal.blackboard.assistance == nil
        assert entity.unit.target == 0
      end

      refute Movement.moving?(dead, 500)
    end

    test "timed panic expiry stops its path and restores walking", %{mob: mob} do
      mob = %{mob | internal: %{mob.internal | running: false}}
      mob = start(mob, Context.new(0))
      moving = Movement.move_along_path(mob, [{100.0, 0.0, 0.0}], [run?: true], 0)
      assert {:failure, result} = BT.tick(BT.action(&Flee.tick/3), moving, Context.new(7_000))
      refute Movement.moving?(result, 7_000)
      refute result.internal.running
      assert Bitwise.band(result.unit.flags, 0x00800000) == 0
    end
  end

  defp mob(_context) do
    %{
      mob: %Mob{
        object: %Object{guid: 1},
        unit: %Unit{health: 100, max_health: 100, level: 50, flags: 0, auras: [], target: 2},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, walk_speed: 2.5, run_speed: 7.0},
        internal: %Internal{world: WorldRef.open(0), running: true, in_combat: true, blackboard: Blackboard.new()}
      }
    }
  end

  defp context(now) do
    entities = %{
      1 => helper(1, 0.0),
      2 => %Observation{
        guid: 2,
        position: {WorldRef.open(0), -3.0, 0.0, 0.0},
        metadata: %{alive?: true, faction_template: %FactionTemplate{id: 1, faction_group: 1}}
      },
      3 => helper(3, 21.0),
      4 => helper(4, 28.0)
    }

    Context.new(now, perception: Perception.new(now, nil, entities, %{mobs: [{4, 28.0}, {3, 21.0}]}))
  end

  defp helper(guid, x) do
    %Observation{
      guid: guid,
      position: {WorldRef.open(0), x, 0.0, 0.0},
      line_of_sight?: true,
      metadata: %{
        assistance_available?: true,
        faction_template: %FactionTemplate{id: 17, flags: 1, faction_group: 8, enemy_group: 1}
      }
    }
  end

  defp start(mob, context \\ context(0)) do
    {mob, blackboard} = Script.run(mob, mob.internal.blackboard, [%ScriptStep{command: :flee, datalong: 1}], 2, context)
    %{mob | internal: %{mob.internal | blackboard: blackboard}}
  end

  defp moving(mob) do
    {{:running, 0, :navigation}, mob} = mob |> start() |> tick(0)
    NavigationResolver.resolve(mob, 0, fn _, _, to, _ -> [to] end)
  end

  defp tick(mob, now), do: BT.tick(BT.action(&SeekAssistance.tick/3), mob, context(now))

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
