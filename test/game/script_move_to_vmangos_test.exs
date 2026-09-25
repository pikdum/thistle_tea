defmodule ThistleTea.Game.ScriptMoveToVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Navigation
  alias ThistleTea.Game.Entity.Logic.AI.Script
  alias ThistleTea.Game.World.Loader.Script, as: ScriptLoader
  alias ThistleTea.Game.WorldRef

  @moduletag :vmangos_db

  describe "loaded random-point movement" do
    test "Horde defenders and Mindless Undead request the authored region without fixed facing" do
      ids = [945_704, 945_804, 1_103_003, 1_103_004]
      scripts = ScriptLoader.load_by_ids(Mangos.CreatureAiScript, ids)
      world = WorldRef.open(1)

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{health: 100},
        internal: %Internal{world: world, creature: %Creature{}}
      }

      steps = scripts |> Map.values() |> List.flatten()
      assert length(steps) == 6

      for step <- steps do
        assert step.command == :move_to
        assert step.datalong == 3
        assert {x, y, z, 5.0} = step.position
        mob = %{mob | movement_block: %MovementBlock{position: {x, y, z, 0.0}}}
        destination = {x + 1, y, z}
        navigation = Navigation.new(%{{1, {x, y, z}, 5.0} => destination})
        context = Context.new(0, navigation: navigation, script_conditions: %{step.condition_id => :met})
        {requested, _} = Script.run(mob, Blackboard.new(), [step], nil, context)
        assert [intent] = requested.internal.navigation_intents
        assert intent.destination == destination
        assert intent.opts[:run?]
        refute Keyword.has_key?(intent.opts, :face_angle)
      end
    end
  end
end
