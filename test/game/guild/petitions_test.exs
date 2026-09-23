defmodule ThistleTea.Game.Guild.PetitionsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Guild
  alias ThistleTea.Game.Guild.Member
  alias ThistleTea.Game.Guild.Petitions

  describe "create/6" do
    test "keeps one charter per owner and validates the guild name" do
      owner = member(1, 1)
      assert {:ok, petition, petitions} = Petitions.create(%Petitions{}, owner, 100, 500, 5, "Fellowship")
      assert petition.id == 5
      assert Petitions.by_owner(petitions, 1) == petition
      assert Petitions.by_id(petitions, 5) == petition
      assert {:error, :already_invited} = Petitions.create(petitions, owner, 100, 501, 6, "Another Guild")
      assert {:error, :invalid_name} = Petitions.create(%Petitions{}, owner, 100, 500, 5, "X")
    end
  end

  describe "sign/4" do
    test "enforces unique accounts, faction, and nine signatures" do
      {:ok, _petition, petitions} = Petitions.create(%Petitions{}, member(1, 1), 100, 500, 5, "Fellowship")
      assert {:error, :cant_sign_own} = Petitions.sign(petitions, 500, member(1, 1), 100)
      assert {:error, :wrong_faction} = Petitions.sign(petitions, 500, member(2, 2), 101)
      assert {:ok, _petition, petitions} = Petitions.sign(petitions, 500, member(2, 1), 101)
      assert {:error, :already_signed} = Petitions.sign(petitions, 500, member(3, 1), 101)

      petitions =
        Enum.reduce(3..10, petitions, fn guid, state ->
          {:ok, _petition, updated} = Petitions.sign(state, 500, member(guid, 1), 100 + guid)
          updated
        end)

      petition = Petitions.by_item(petitions, 500)
      assert Petitions.complete?(petition)
      assert length(Petitions.signers(petition)) == 9
      assert {:error, :complete} = Petitions.sign(petitions, 500, member(11, 1), 111)

      petitions = Petitions.revoke_signer(petitions, 2)
      refute Petitions.complete?(Petitions.by_item(petitions, 500))
      assert {:ok, _petition, petitions} = Petitions.delete(petitions, 500)
      assert Petitions.by_owner(petitions, 1) == nil
    end
  end

  describe "create_from_petition/5" do
    test "creates founder and eligible signers atomically" do
      signers = Enum.map(2..10, &member(&1, 1))
      founder = member(1, 1)

      assert {:error, :need_more} =
               Guild.create_from_petition(%Guild{}, founder, Enum.take(signers, 8), "Fellowship", ~D[2026-09-22])

      assert {:error, :need_more} =
               Guild.create_from_petition(%Guild{}, founder, signers ++ [member(11, 1)], "Fellowship", ~D[2026-09-22])

      assert {:ok, group, guilds} = Guild.create_from_petition(%Guild{}, founder, signers, "Fellowship", ~D[2026-09-22])
      assert map_size(group.members) == 10
      assert Guild.member(group, 1).rank == 0
      assert Enum.all?(signers, &(Guild.member(group, &1.guid).rank == 4))
      assert Guild.group_of(guilds, 10) == group

      assert {:error, :already_in_guild} =
               Guild.create_from_petition(guilds, founder, signers, "New Guild", ~D[2026-09-22])
    end
  end

  defp member(guid, race), do: %Member{guid: guid, name: "Player#{guid}", race: race, class: 1, level: 20}
end
