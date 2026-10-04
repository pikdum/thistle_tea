defmodule ThistleTea.Game.Core.InstanceScript.StratholmeVmangosTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.SQL
  alias ThistleTea.DB.Mangos.Repo
  alias ThistleTea.Game.Core.Instance
  alias ThistleTea.Game.Core.InstanceScript.Effects

  @moduletag :vmangos_db

  describe "live-side content" do
    test "each scripted postbox summons Malown at its own spawn" do
      boxes =
        rows("""
        SELECT g.id, g.position_x, g.position_y, g.position_z FROM gameobject g
        JOIN gameobject_template t ON t.entry = g.id
        WHERE g.map = 329 AND t.script_name = 'go_stratholme_postbox' ORDER BY g.id
        """)

      assert length(boxes) == 6

      for [entry, x, y, z] <- boxes do
        {world, nil, instances} = Instance.enter(%Instance{}, 329, {:player, 100}, 100, "instance_stratholme")

        instances =
          Enum.reduce(1..2, instances, fn _use, instances ->
            {:ok, _effects, instances} = Instance.game_object_used(instances, world, entry)
            instances
          end)

        assert {:ok, effects, _instances} = Instance.game_object_used(instances, world, entry)
        assert %Effects.SummonCreature{position: {^x, ^y, ^z, _}} = List.last(effects)
      end
    end

    test "Timmy's spawner is a Crimson Guardsman and Willey's gate stands open" do
      assert rows("SELECT id FROM creature WHERE guid = 54070") == [[10_418]]
      assert rows("SELECT state FROM gameobject WHERE map = 329 AND id = 175969") == [[0]]
    end

    test "pins the boss lines" do
      ids = "6150, 6441, 6442, 6447, 6504, 6530"
      assert rows("SELECT count(*) FROM broadcast_text WHERE entry IN (#{ids})") == [[6]]
    end
  end

  defp rows(sql), do: SQL.query!(Repo, sql, []).rows
end
