defmodule ThistleTea.Game.World.Entity.Mob.FireworkGuyTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Spawn
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Entity.Mob.FireworkGuy
  alias ThistleTea.Test.Unique

  describe "launch/1" do
    test "sends the rocket up and credits the player who fired it" do
      player = Guid.from_low_guid(:player, Unique.integer())
      events = 15_882 |> guy(player) |> FireworkGuy.launch() |> events()

      assert [
               %Effects.SummonGameObject{entry: 180_851, duration_ms: 5_000, position: position},
               %Effects.QuestKillCredit{player_guid: ^player, creature_entry: 15_893}
             ] = events

      assert position == {10.0, 20.0, 33.0, 0.0}
    end

    test "a lucky cluster brings Lunar Fortune three seconds after it bursts" do
      guy = guy(15_918, nil)
      events = guy |> FireworkGuy.launch() |> events()

      assert length(Enum.filter(events, &is_struct(&1, Effects.SummonGameObject))) == 5
      refute Enum.any?(events, &is_struct(&1, Effects.QuestKillCredit))
      assert %Effects.ScriptSteps{steps: [step], target_guid: target, duration_ms: 3_000} = List.last(events)
      assert target == guy.object.guid
      assert %ScriptStep{command: :cast_spell, datalong: 26_522, target_self?: true} = step
    end

    test "any other creature launches nothing" do
      mob = guy(15_466, nil)
      assert FireworkGuy.launch(mob) == mob
    end
  end

  defp guy(entry, summoner) do
    %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, entry, Unique.integer()), entry: entry},
      movement_block: %MovementBlock{position: {10.0, 20.0, 30.0, 1.0}},
      internal: %Internal{world: WorldRef.open(0), spawn: %Spawn{summoner_guid: summoner}}
    }
  end

  defp events(%Mob{internal: %{events: events}}), do: events
end
