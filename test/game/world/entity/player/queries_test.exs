defmodule ThistleTea.Game.World.Entity.Player.QueriesTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Network.Message.SmsgNameQueryResponse
  alias ThistleTea.Game.World.Entity.Player.Queries
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Test.Unique

  describe "name/1" do
    test "answers from the published unit name" do
      guid = Guid.from_low_guid(:player, Unique.integer())
      Metadata.put(guid, %{name: "Thistle", race: 2, gender: 1, class: 4})
      on_exit(fn -> Metadata.delete(guid) end)

      assert Queries.name(guid) == %SmsgNameQueryResponse{
               guid: guid,
               character_name: "Thistle",
               realm_name: "",
               race: 2,
               gender: 1,
               class: 4
             }
    end

    test "names an unknown guid Unknown" do
      guid = Guid.from_low_guid(:player, 0xFFFFFF00 + rem(Unique.integer(), 0xFF))

      assert %SmsgNameQueryResponse{character_name: "Unknown", race: 0, class: 0} = Queries.name(guid)
    end
  end
end
