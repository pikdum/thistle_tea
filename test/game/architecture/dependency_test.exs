defmodule ThistleTea.Game.Architecture.DependencyTest do
  use ExUnit.Case, async: true

  @root Path.expand("../../..", __DIR__)

  @allowed_logic_boundaries MapSet.new([
                              {"lib/game/entity/logic/ai/bt/combat.ex", "ThistleTea.Game.World"},
                              {"lib/game/entity/logic/ai/bt/combat.ex", "ThistleTea.Game.World.Loader.Item"},
                              {"lib/game/entity/logic/ai/bt/combat.ex", "ThistleTea.Game.World.Metadata"},
                              {"lib/game/entity/logic/ai/bt/mob.ex", "ThistleTea.Game.World"},
                              {"lib/game/entity/logic/ai/bt/mob.ex", "ThistleTea.Game.World.Metadata"},
                              {"lib/game/entity/logic/casting.ex", "ThistleTea.Game.World"},
                              {"lib/game/entity/logic/casting.ex", "ThistleTea.Game.World.Metadata"},
                              {"lib/game/entity/logic/core.ex", "ThistleTea.Game.Network.UpdateObject"},
                              {"lib/game/entity/logic/hostility.ex", "ThistleTea.Game.World.Metadata"},
                              {"lib/game/entity/logic/hostility.ex", "ThistleTea.Game.World.System.Duel"},
                              {"lib/game/entity/logic/player_combat.ex", "ThistleTea.Game.World"},
                              {"lib/game/entity/logic/player_combat.ex", "ThistleTea.Game.World.Metadata"},
                              {"lib/game/entity/logic/shaman.ex", "ThistleTea.Game.World.Loader.Spell"},
                              {"lib/game/entity/logic/spell_effect/script.ex",
                               "ThistleTea.Game.World.Loader.SpellPetAura"},
                              {"lib/game/entity/logic/talents.ex", "ThistleTea.Game.World.Loader.Talent"},
                              {"lib/game/entity/logic/threat.ex", "ThistleTea.Game.World"},
                              {"lib/game/entity/logic/threat.ex", "ThistleTea.Game.World.Metadata"}
                            ])

  @spatial_index_boundaries MapSet.new([
                              "lib/game/world.ex",
                              "lib/game/world/position.ex",
                              "lib/game/world/spatial_hash.ex"
                            ])

  test "pure logic does not acquire new boundary dependencies" do
    assert logic_boundary_dependencies() == @allowed_logic_boundaries
  end

  test "event interpreters do not depend on their caller process" do
    violations =
      event_sink_files()
      |> Enum.reject(&String.ends_with?(&1, "/context.ex"))
      |> Enum.filter(fn path ->
        source = File.read!(path)
        Regex.match?(~r/\bself\(\)/, source) or String.contains?(source, "Network.send_packet")
      end)

    assert violations == []
  end

  test "mutable spatial index access stays behind world boundaries" do
    users =
      Path.wildcard(Path.join([@root, "lib/**/*.ex"]))
      |> Enum.filter(fn path ->
        path
        |> File.read!()
        |> String.contains?("ThistleTea.Game.World.SpatialHash")
      end)
      |> MapSet.new(&Path.relative_to(&1, @root))

    assert users == @spatial_index_boundaries
  end

  test "target and movement rules stay outside concrete event interpreters" do
    violations =
      ["combat.ex", "movement.ex", "spells.ex"]
      |> Enum.map(&Path.join([@root, "lib/game/entity/event_sink", &1]))
      |> Enum.filter(fn path ->
        source = File.read!(path)

        Enum.any?(
          ["SpellTargetResolver", "World.Loader", "World.Pathfinding"],
          &String.contains?(source, &1)
        )
      end)

    assert violations == []
  end

  defp logic_boundary_dependencies do
    Path.wildcard(Path.join([@root, "lib/game/entity/logic/**/*.ex"]))
    |> Enum.flat_map(fn path ->
      path
      |> File.read!()
      |> boundary_modules()
      |> Enum.map(&{Path.relative_to(path, @root), &1})
    end)
    |> MapSet.new()
  end

  defp boundary_modules(source) do
    ~r/ThistleTea\.Game\.(?:Network|World(?!Ref))(?:\.[A-Z][A-Za-z0-9_]*)*/
    |> Regex.scan(source, capture: :first)
    |> List.flatten()
  end

  defp event_sink_files do
    [
      Path.join([@root, "lib/game/entity/event_sink.ex"])
      | Path.wildcard(Path.join([@root, "lib/game/entity/event_sink/*.ex"]))
    ]
  end
end
