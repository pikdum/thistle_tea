defmodule ThistleTea.Game.Architecture.DependencyTest do
  use ExUnit.Case, async: true

  @root Path.expand("../../..", __DIR__)

  @random_sources MapSet.new([
                    "lib/game/core/math.ex",
                    "lib/game/core/rolls.ex"
                  ])

  @allowed_core_random_draws MapSet.new([
                               "lib/game/core/ai/creature_spell.ex",
                               "lib/game/core/aura.ex",
                               "lib/game/core/aura/class_script.ex",
                               "lib/game/core/aura/dispel.ex",
                               "lib/game/core/aura/periodic_damage.ex",
                               "lib/game/core/aura/proc_chance.ex",
                               "lib/game/core/aura/proc_spell.ex",
                               "lib/game/core/aura/transition.ex",
                               "lib/game/core/class/racial.ex",
                               "lib/game/core/class/shaman.ex",
                               "lib/game/core/combat.ex",
                               "lib/game/core/combat/attack_table.ex",
                               "lib/game/core/entity/game_object.ex",
                               "lib/game/core/loot.ex",
                               "lib/game/core/loot/loot_roll.ex",
                               "lib/game/core/profession/engineering/death_ray.ex",
                               "lib/game/core/reputation.ex",
                               "lib/game/core/skills.ex",
                               "lib/game/core/spell/cast_pushback.ex",
                               "lib/game/core/spell/effect.ex",
                               "lib/game/core/spell/proc.ex",
                               "lib/game/core/spell/spell_resist.ex",
                               "lib/game/core/spell/target_trigger.ex"
                             ])

  @spatial_index_boundaries MapSet.new([
                              "lib/game/world.ex",
                              "lib/game/world/position.ex",
                              "lib/game/world/spatial_hash.ex"
                            ])

  test "core files never reference the world, network, or seed databases" do
    assert core_outer_references() == MapSet.new()
  end

  test "core never reads the clock" do
    readers =
      core_files()
      |> Enum.filter(&(File.read!(&1) =~ ~r/\bTime\.now\b|System\.(monotonic|system|os)_time|utc_now|:os\.timestamp/))
      |> MapSet.new(&Path.relative_to(&1, @root))

    assert readers == MapSet.new(["lib/game/core/time.ex"])
  end

  test "core files do not gain new ambient random draws" do
    drawers =
      core_files()
      |> Enum.filter(&(File.read!(&1) =~ ~r/:rand\.|Enum\.(random|shuffle|take_random)|Math\.random_int/))
      |> MapSet.new(&Path.relative_to(&1, @root))
      |> MapSet.difference(@random_sources)

    assert drawers == @allowed_core_random_draws
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
      |> Enum.map(&Path.join([@root, "lib/game/world/entity/event_sink", &1]))
      |> Enum.filter(fn path ->
        source = File.read!(path)

        Enum.any?(
          ["SpellTargetResolver", "World.Loader", "World.Pathfinding"],
          &String.contains?(source, &1)
        )
      end)

    assert violations == []
  end

  test "condition-aware gameplay paths do not query Mangos" do
    violations =
      condition_runtime_files()
      |> Enum.filter(fn path ->
        source = File.read!(path)
        String.contains?(source, "ThistleTea.DB.Mangos") or String.contains?(source, "Mangos.Repo")
      end)
      |> Enum.map(&Path.relative_to(&1, @root))

    assert violations == []
  end

  defp core_outer_references do
    core_files()
    |> Enum.flat_map(fn path ->
      path
      |> File.read!()
      |> outer_modules()
      |> Enum.map(&{Path.relative_to(path, @root), &1})
    end)
    |> MapSet.new()
  end

  defp outer_modules(source) do
    {_ast, modules} =
      source
      |> Code.string_to_quoted!()
      |> Macro.prewalk([], fn
        {:__aliases__, _meta, [:ThistleTea | _rest] = parts} = node, acc ->
          {node, [inspect(Module.concat(parts)) | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.filter(modules, &Regex.match?(~r/^ThistleTea\.(?:Game\.(?:Network|World)|DB)(?:\.|$)/, &1))
  end

  defp core_files, do: Path.wildcard(Path.join([@root, "lib/game/core/**/*.ex"]))

  defp event_sink_files do
    [
      Path.join([@root, "lib/game/world/entity/event_sink.ex"])
      | Path.wildcard(Path.join([@root, "lib/game/world/entity/event_sink/*.ex"]))
    ]
  end

  defp condition_runtime_files do
    relative = [
      "lib/game/core/condition.ex",
      "lib/game/core/loot.ex",
      "lib/game/core/loot/loot_session.ex",
      "lib/game/core/ai/event_ai.ex",
      "lib/game/core/ai/script.ex",
      "lib/game/world/entity/player/area_triggers.ex",
      "lib/game/world/entity/player/gossip.ex",
      "lib/game/world/entity/player/gossip_condition.ex",
      "lib/game/world/entity/player/looting.ex",
      "lib/game/world/entity/player/vendor.ex",
      "lib/game/world/inbound/interaction.ex",
      "lib/game/world/inbound/vendor.ex"
    ]

    Enum.map(relative, &Path.join(@root, &1)) ++
      Path.wildcard(Path.join([@root, "lib/game/core/condition/**/*.ex"]))
  end
end
