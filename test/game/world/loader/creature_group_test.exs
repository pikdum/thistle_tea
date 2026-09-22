defmodule ThistleTea.Game.World.Loader.CreatureGroupTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Logic.CreatureGroup
  alias ThistleTea.Game.World.Loader.CreatureGroup, as: Loader

  describe "build/1" do
    test "indexes leaders and followers without applying the leader's own row flags" do
      rows = [
        {0, %Mangos.CreatureGroup{leader_guid: 1, member_guid: 1, flags: 255}},
        {0, %Mangos.CreatureGroup{leader_guid: 1, member_guid: 2, dist: 4.0, angle: 1.5, flags: 2}}
      ]

      catalog = Loader.build(rows)
      assert catalog[{0, 1}] == catalog[{0, 2}]
      assert %CreatureGroup{flags: 2, members: %{2 => %{distance: 4.0, angle: 1.5}}} = catalog[{0, 1}]
      assert catalog[{1, 1}] == nil
    end
  end

  describe "load_all/0" do
    @tag :vmangos_db
    test "loads the Den Mother and Thistle Cubs as one shared-evade group" do
      assert :ok = Loader.load_all()
      group = Loader.get(1, 37_523)
      assert group.leader == 37_523
      assert group.flags == 6
      assert group == Loader.get(1, 37_567)
      assert CreatureGroup.member_ids(group) |> length() > 2
      assert Loader.get(0, 37_523) == nil
    end
  end
end
