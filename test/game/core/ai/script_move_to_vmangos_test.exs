defmodule ThistleTea.Game.Core.AI.ScriptMoveToVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Navigation
  alias ThistleTea.Game.Core.AI.Script
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Loader.Script, as: ScriptLoader

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
