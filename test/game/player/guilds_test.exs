defmodule ThistleTea.Game.Player.GuildsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Guild
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Guilds
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.System.Guild, as: GuildSystem

  describe "create/2" do
    test "publishes a founder and returns a client-readable guild query", %{founder: founder, name: name} do
      state = Guilds.create(founder, name)
      group = GuildSystem.group_of(founder.guid)

      assert group.name == name
      assert state.character.player.guild_id == group.id
      assert state.character.player.guild_rank == 0
      assert CharacterStore.get(state.character.id).player.guild_id == group.id
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgGuildCommandResult{result: :ok}}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgGuildEvent{event: :joined}}}

      assert Guilds.query(state, group.id) == state
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgGuildQueryResponse{guild: ^group}}}
      assert Guilds.roster(state) == state
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgGuildRoster{guild: ^group, entries: [entry]}}}
      assert entry.guid == founder.guid
      assert entry.rank == 0
    end
  end

  describe "invite/2" do
    test "joins a same-faction target and routes guild chat to members", %{founder: founder, target: target, name: name} do
      founder = Guilds.create(founder, name)
      drain_packets()

      assert Guilds.invite(founder, target.character.internal.name) == founder
      assert_receive {:target_packet, %Message.SmsgGuildInvite{guild_name: ^name}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgGuildCommandResult{result: :ok}}}

      target = Guilds.accept(target)
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgGuildEvent{event: :motd}}}
      assert target.character.player.guild_id == founder.character.player.guild_id
      assert target.character.player.guild_rank == 4
      assert Guild.member(GuildSystem.group_of(founder.guid), target.guid).rank == 4
      drain_packets()

      assert Guilds.chat(founder, 3, 0, "hello guild") == founder
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{message: "hello guild"}}}
      assert_receive {:target_packet, %Message.SmsgMessagechat{message: "hello guild"}}

      assert Guilds.chat(target, 4, 0, "officer-only") == target
      refute_receive {:target_packet, %Message.SmsgMessagechat{message: "officer-only"}}
    end

    test "rank changes and disband clear an offline member's saved projection", %{
      founder: founder,
      target: target,
      target_owner: target_owner,
      name: name
    } do
      founder = Guilds.create(founder, name)
      Guilds.invite(founder, target.character.internal.name)
      target = Guilds.accept(target)
      group_id = founder.character.player.guild_id

      monitor = Process.monitor(target_owner)
      Process.exit(target_owner, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^target_owner, :killed}

      assert Guilds.promote(founder, target.character.internal.name) == founder
      assert CharacterStore.get(target.character.id).player.guild_rank == 3

      Guilds.roster(founder)
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgGuildRoster{entries: entries}}}
      assert Enum.find(entries, &(&1.guid == target.guid)).online? == false

      founder = Guilds.disband(founder)
      assert founder.character.player.guild_id == 0
      assert CharacterStore.get(target.character.id).player.guild_id == 0
      assert GuildSystem.group(group_id) == nil
    end
  end

  setup do
    suffix = System.unique_integer([:positive])
    name = "Guild #{suffix}"
    founder_character = character("Founder#{suffix}", 1)
    target_character = character("Target#{suffix}", 3)
    {:ok, _} = Entity.register(founder_character.object.guid)
    parent = self()

    target_owner =
      spawn(fn ->
        {:ok, _} = Entity.register(target_character.object.guid)
        send(parent, :target_ready)
        forward_packets(parent)
      end)

    assert_receive :target_ready

    on_exit(fn ->
      GuildSystem.disband(founder_character.object.guid)
      Entity.unregister(founder_character.object.guid)
      Process.exit(target_owner, :kill)
      :ets.delete(CharacterStore, founder_character.id)
      :ets.delete(CharacterStore, target_character.id)
    end)

    %{
      founder: %State{guid: founder_character.object.guid, character: founder_character, ready: true},
      target: %State{guid: target_character.object.guid, character: target_character, ready: true},
      target_owner: target_owner,
      name: name
    }
  end

  defp character(name, race) do
    id = System.unique_integer([:positive])

    CharacterStore.put(%Character{
      id: id,
      object: %Object{guid: Guid.from_low_guid(:player, id)},
      player: %Player{},
      unit: %Unit{race: race, class: 1, level: 10},
      internal: %Internal{name: name}
    })
  end

  defp forward_packets(parent) do
    receive do
      {:"$gen_cast", {:send_packet, packet}} ->
        send(parent, {:target_packet, packet})
        forward_packets(parent)

      :sync_guild_membership ->
        send(parent, :target_synced)
        forward_packets(parent)
    end
  end

  defp drain_packets do
    receive do
      {:"$gen_cast", {:send_packet, _packet}} -> drain_packets()
      {:target_packet, _packet} -> drain_packets()
    after
      10 -> :ok
    end
  end
end
