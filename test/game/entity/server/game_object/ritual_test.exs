defmodule ThistleTea.Game.Entity.Server.GameObject.RitualTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal.Ritual
  alias ThistleTea.Game.Entity.Server.GameObject.Ritual, as: RitualServer

  describe "use/3" do
    test "completes after the required unique grouped participants" do
      ritual = %Ritual{
        owner_guid: 1,
        target_guid: 9,
        required_participants: 3,
        casters_grouped?: true,
        users: MapSet.new([1])
      }

      {ritual, :waiting} = RitualServer.use(ritual, 2, true)
      {same, :ignored} = RitualServer.use(ritual, 2, true)
      assert same == ritual

      {ritual, :complete} = RitualServer.use(ritual, 3, true)
      assert ritual.completed?
      assert ritual.users == MapSet.new([1, 2, 3])
    end

    test "ignores the owner and ungrouped helpers" do
      ritual = %Ritual{
        owner_guid: 1,
        required_participants: 3,
        casters_grouped?: true,
        users: MapSet.new([1])
      }

      assert {^ritual, :ignored} = RitualServer.use(ritual, 1, true)
      assert {^ritual, :ignored} = RitualServer.use(ritual, 2, false)
    end

    test "allows ungrouped helpers when the template does not require grouping" do
      ritual = %Ritual{owner_guid: 1, required_participants: 2, users: MapSet.new([1])}

      assert {%Ritual{completed?: true}, :complete} = RitualServer.use(ritual, 2, false)
    end
  end
end
