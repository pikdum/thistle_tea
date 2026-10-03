defmodule ThistleTea.Game.World.Entity.Player.WhoListTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DB.DBC
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Guild.Member
  alias ThistleTea.Game.Core.Who.Query
  alias ThistleTea.Game.Network.Message.SmsgWho
  alias ThistleTea.Game.Network.Message.SmsgWho.WhoPlayer
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.Player.WhoList
  alias ThistleTea.Game.World.Loader.Exploration
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.System.Guild, as: GuildSystem
  alias ThistleTea.Test.Unique

  @human 1
  @orc 2
  @warrior 1

  describe "send/2" do
    setup [:zone, :players]

    test "lists online players of the asker's team in their zone, with their guild", context do
      %{asker: asker, zone: zone, tag: tag} = context
      state = %{ready: true, guid: asker, character: %Character{id: asker}}

      assert ^state = WhoList.send(state, %Query{name: tag})

      assert_receive {:"$gen_cast", {:send_packet, %SmsgWho{players: players}}}
      assert [%WhoPlayer{guild: ^tag, area: ^zone}, %WhoPlayer{guild: "", area: ^zone}] = players
      assert Enum.map(players, & &1.name) == ["#{tag}Ally", "#{tag}Asker"]
    end
  end

  defp zone(_context) do
    zone = Unique.integer()
    subzone = Unique.integer()

    :ets.insert(Exploration, [
      {{:area, zone}, %DBC.AreaTable{id: zone, parent_area_table: 0, name: "Testlands"}},
      {{:area, subzone}, %DBC.AreaTable{id: subzone, parent_area_table: zone, name: "Testvale"}}
    ])

    on_exit(fn -> Enum.each([zone, subzone], &:ets.delete(Exploration, {:area, &1})) end)
    %{zone: zone, subzone: subzone}
  end

  defp players(%{subzone: subzone}) do
    tag = "Who#{Unique.integer()}"
    map_id = Unique.integer()
    [asker, ally, enemy] = guids = Enum.map(1..3, fn _ -> Unique.integer() end)

    for {guid, name, race} <- [{asker, "Asker", @human}, {ally, "Ally", @human}, {enemy, "Enemy", @orc}] do
      CharacterStore.put(%Character{id: guid, account_id: Unique.integer()})
      {:ok, _} = Entity.register(guid)
      Metadata.put(guid, %{name: tag <> name, race: race, class: @warrior, level: 30, area: subzone})
      SpatialHash.update(:players, guid, map_id, 1.0, 2.0, 3.0)
    end

    {:ok, _group} = GuildSystem.create(%Member{guid: ally, name: tag <> "Ally", race: @human, class: 1, level: 30}, tag)

    on_exit(fn ->
      GuildSystem.disband(ally)

      for guid <- guids do
        CharacterStore.delete(guid)
        Metadata.delete(guid)
        SpatialHash.remove(:players, guid)
      end
    end)

    %{asker: asker, tag: tag}
  end
end
