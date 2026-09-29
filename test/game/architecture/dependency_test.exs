defmodule ThistleTea.Game.Architecture.DependencyTest do
  use ExUnit.Case, async: true

  @root Path.expand("../../..", __DIR__)

  @allowed_logic_boundaries MapSet.new([
                              {"lib/game/core/ai/bt/combat.ex", "ThistleTea.Game.World.Spell.SpellTargetResolver"},
                              {"lib/game/core/ai/bt/mob.ex", "ThistleTea.Game.World"},
                              {"lib/game/core/ai/bt/mob.ex", "ThistleTea.Game.World.Metadata"},
                              {"lib/game/core/class/shaman.ex", "ThistleTea.Game.World.Loader.Spell"},
                              {"lib/game/core/combat/hostility.ex", "ThistleTea.Game.World.Metadata"},
                              {"lib/game/core/combat/hostility.ex", "ThistleTea.Game.World.System.Duel"},
                              {"lib/game/core/combat/threat.ex", "ThistleTea.Game.World"},
                              {"lib/game/core/combat/threat.ex", "ThistleTea.Game.World.Metadata"},
                              {"lib/game/core/entity.ex", "ThistleTea.Game.Network.UpdateObject"},
                              {"lib/game/core/entity/character.ex", "ThistleTea.Game.World.ItemStore"},
                              {"lib/game/core/entity/character.ex", "ThistleTea.Game.World.Loader.Item"},
                              {"lib/game/core/entity/character.ex", "ThistleTea.Game.World.Loader.ItemEnchantment"},
                              {"lib/game/core/entity/character.ex", "ThistleTea.Game.World.Loader.ItemSet"},
                              {"lib/game/core/entity/character.ex", "ThistleTea.Game.World.Loader.Spell"},
                              {"lib/game/core/entity/component/movement_block.ex",
                               "ThistleTea.Game.Network.BinaryUtils"},
                              {"lib/game/core/entity/component/player.ex", "ThistleTea.Game.Network.UpdateObject"},
                              {"lib/game/core/entity/component/unit.ex", "ThistleTea.Game.Network.UpdateObject"},
                              {"lib/game/core/entity/corpse.ex", "ThistleTea.Game.Network.UpdateObject"},
                              {"lib/game/core/party.ex", "ThistleTea.Game.World.System.Party"},
                              {"lib/game/core/party/member_stats.ex", "ThistleTea.Game.Network.BinaryUtils"},
                              {"lib/game/core/player/talents.ex", "ThistleTea.Game.World.Loader.Talent"},
                              {"lib/game/core/spell/cast_context.ex", "ThistleTea.Game.World.Loader.SpellThreat"},
                              {"lib/game/core/spell/casting.ex", "ThistleTea.Game.World"},
                              {"lib/game/core/spell/casting.ex", "ThistleTea.Game.World.Metadata"},
                              {"lib/game/core/spell/casting.ex", "ThistleTea.Game.World.Spell.SpellTargetResolver"},
                              {"lib/game/core/spell/spell_effect/script.ex",
                               "ThistleTea.Game.World.Loader.SpellPetAura"},
                              {"lib/game/core/spell/target_codec.ex", "ThistleTea.Game.Network.BinaryUtils"}
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

  defp logic_boundary_dependencies do
    Path.wildcard(Path.join([@root, "lib/game/core/**/*.ex"]))
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
      "lib/game/network/message/cmsg_buy_item.ex",
      "lib/game/network/message/cmsg_gossip_hello.ex",
      "lib/game/network/message/cmsg_list_inventory.ex"
    ]

    Enum.map(relative, &Path.join(@root, &1)) ++
      Path.wildcard(Path.join([@root, "lib/game/core/condition/**/*.ex"]))
  end
end
