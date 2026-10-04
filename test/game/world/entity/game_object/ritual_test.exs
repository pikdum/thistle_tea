defmodule ThistleTea.Game.World.Entity.GameObject.RitualTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Entity.Component.Internal.Ritual
  alias ThistleTea.Game.World.Entity.GameObject.Ritual, as: RitualServer

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

    test "a placed ritual groups its helpers with the first participant" do
      altar = %Ritual{required_participants: 3, casters_grouped?: true, persistent?: true}

      {altar, :waiting} = RitualServer.use(altar, 1, false)
      assert altar.first_user_guid == 1
      assert RitualServer.anchor(altar) == 1

      assert {^altar, :ignored} = RitualServer.use(altar, 2, false)
      {altar, :waiting} = RitualServer.use(altar, 2, true)
      {altar, :complete} = RitualServer.use(altar, 3, true)

      assert altar.users == MapSet.new([1, 2, 3])
      assert altar.first_user_guid == 1
    end
  end

  describe "leave/2" do
    test "a persistent ritual can complete again once too few participants remain" do
      ritual = %Ritual{owner_guid: 1, required_participants: 2, persistent?: true, users: MapSet.new([1])}
      {ritual, :complete} = RitualServer.use(ritual, 2, true)

      ritual = RitualServer.leave(ritual, 2)

      refute ritual.completed?
      assert {%Ritual{completed?: true}, :complete} = RitualServer.use(ritual, 3, true)
    end

    test "the next participant leads a placed ritual its participants all left" do
      {altar, :waiting} = RitualServer.use(%Ritual{required_participants: 3}, 1, false)

      altar = RitualServer.leave(altar, 1)

      assert altar.first_user_guid == nil
      assert {%Ritual{first_user_guid: 2}, :waiting} = RitualServer.use(altar, 2, false)
    end
  end

  describe "reset/1" do
    test "clears a completed placed ritual for its next use" do
      altar = %Ritual{required_participants: 1, persistent?: true}
      {altar, :complete} = RitualServer.use(altar, 1, false)

      assert %Ritual{users: users, first_user_guid: nil, completed?: false} = RitualServer.reset(altar)
      assert users == MapSet.new()
    end
  end
end
