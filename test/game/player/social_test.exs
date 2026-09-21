defmodule ThistleTea.Game.Player.SocialTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Duel
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.ChatStatus
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Registry
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Groups
  alias ThistleTea.Game.Player.Social, as: PlayerSocial
  alias ThistleTea.Game.Social.Friend
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Loader.Exploration
  alias ThistleTea.Game.World.Presence
  alias ThistleTea.Game.World.SocialStore
  alias ThistleTea.Game.World.System.Duel, as: DuelSystem
  alias ThistleTea.Game.World.System.Party, as: PartySystem
  alias ThistleTea.Game.WorldRef

  setup [:characters]

  describe "add/3" do
    test "resolves offline names and reports self, missing, duplicate, and faction failures", %{
      owner: owner,
      target: target,
      enemy: enemy
    } do
      assert PlayerSocial.add(owner, :friend, String.downcase(target.character.internal.name)) == owner
      assert_status(7, target.guid)
      PlayerSocial.add(owner, :friend, target.character.internal.name)
      assert_status(8, target.guid)
      PlayerSocial.add(owner, :friend, owner.character.internal.name)
      assert_status(9, owner.guid)
      PlayerSocial.add(owner, :friend, enemy.character.internal.name)
      assert_status(10, enemy.guid)
      PlayerSocial.add(owner, :friend, "Missing")
      assert_status(4, 0)
      PlayerSocial.add(owner, :ignore, "Missing")
      assert_status(13, 0)
      PlayerSocial.add(owner, :ignore, enemy.character.internal.name)
      assert_status(15, enemy.guid)
      assert SocialStore.ignores?(owner.guid, enemy.guid)
    end

    test "adds an online friend with current zone, level, class, and DND status", %{owner: owner, target: target} do
      target = %{target.character | internal: %{target.character.internal | chat_status: %ChatStatus{mode: :dnd}}}
      Registry.register(target.object.guid)
      publish(target)
      PlayerSocial.add(owner, :friend, target.internal.name)

      assert_receive {:"$gen_cast",
                      {:send_packet,
                       %Message.SmsgFriendStatus{result: 6, friend: %Friend{status: 4, zone: 12, level: 50, class: 8}}}}
    end

    test "does not mutate lists before world entry", %{owner: owner, target: target} do
      state = %{owner | ready: false}
      assert PlayerSocial.add(state, :friend, target.character.internal.name) == state
      assert SocialStore.get(owner.guid).friends == MapSet.new()
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgFriendStatus{}}}
    end
  end

  describe "list/1" do
    test "retains lists across presence cleanup and refreshes online details", %{owner: owner, target: target} do
      PlayerSocial.add(owner, :friend, target.character.internal.name)
      PlayerSocial.add(owner, :ignore, target.character.internal.name)
      assert_status(7, target.guid)
      assert_status(15, target.guid)
      Presence.leave(owner.character)
      publish(owner.character)
      PlayerSocial.send_lists(owner.character)
      target_guid = target.guid

      assert_receive {:"$gen_cast",
                      {:send_packet, %Message.SmsgFriendList{friends: [%Friend{guid: ^target_guid, status: 0}]}}}

      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgIgnoreList{guids: [^target_guid]}}}

      Registry.register(target.guid)
      publish(target.character)
      assert_status(2, target.guid)
      afk = %{target.character | internal: %{target.character.internal | chat_status: %ChatStatus{mode: :afk}}}
      Presence.sync(afk, %{level: 51})
      PlayerSocial.list(owner)
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgFriendList{friends: [%Friend{status: 2, level: 51}]}}}
      Presence.leave(target.character)
      assert_status(3, target.guid)
      Presence.leave(target.character)
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgFriendStatus{}}}
    end
  end

  describe "remove/3" do
    test "preserves ignore membership and stops future friend notifications", %{owner: owner, target: target} do
      PlayerSocial.add(owner, :friend, target.character.internal.name)
      PlayerSocial.add(owner, :ignore, target.character.internal.name)
      assert_status(7, target.guid)
      assert_status(15, target.guid)
      PlayerSocial.remove(owner, :friend, target.guid)
      assert_status(5, target.guid)
      assert SocialStore.ignores?(owner.guid, target.guid)
      Registry.register(target.guid)
      publish(target.character)
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgFriendStatus{}}}
      PlayerSocial.remove(owner, :ignore, target.guid)
      assert_status(16, target.guid)
      refute SocialStore.ignores?(owner.guid, target.guid)
    end
  end

  describe "ignored/2" do
    test "acknowledges only a stored ignore relationship", %{owner: owner, target: target} do
      Registry.register(target.guid)
      PlayerSocial.ignored(owner, target.guid)
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgMessagechat{}}}
      PlayerSocial.add(owner, :ignore, target.character.internal.name)
      PlayerSocial.ignored(owner, target.guid)
      owner_guid = owner.guid

      assert_receive {:"$gen_cast",
                      {:send_packet, %Message.SmsgMessagechat{chat_type: 0x16, sender_guid: ^owner_guid} = packet}}

      assert packet.message == owner.character.internal.name
    end
  end

  describe "group invitations" do
    test "rejects ignored inviters and resumes after removal", %{owner: owner, target: target} do
      Registry.register(target.guid)
      publish(target.character)
      PlayerSocial.add(target, :ignore, owner.character.internal.name)
      assert_status(15, owner.guid)
      Groups.invite(owner, target.character.internal.name)
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgPartyCommandResult{result: 8}}}
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgGroupInvite{}}}
      assert PartySystem.accept(target.guid, target.character.internal.name) == {:error, :not_invited}

      PlayerSocial.remove(target, :ignore, owner.guid)
      Groups.invite(owner, String.downcase(target.character.internal.name))
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgGroupInvite{}}}
      assert {:ok, _} = PartySystem.accept(target.guid, target.character.internal.name)
    end
  end

  describe "duel invitations" do
    test "checks ignore state before creating a duel and refreshes admission after removal", %{
      owner: owner,
      target: target
    } do
      Registry.register(target.guid)
      publish(target.character)
      PlayerSocial.add(target, :ignore, owner.character.internal.name)
      world = WorldRef.open(0)
      admission = DuelSystem.challenge_admission(owner.guid, target.guid, world)
      assert admission.opponent_ignores?
      assert Duel.validate_admission(admission) == {:error, :ignored}

      assert DuelSystem.challenge(%{
               initiator_guid: owner.guid,
               opponent_guid: target.guid,
               initiator_level: 50,
               world: world,
               entry: 21_680,
               flag_position: {0.0, 0.0, 0.0},
               orientation: 0.0
             }) == {:error, :ignored}

      assert DuelSystem.match(owner.guid) == nil
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgDuelRequested{}}}
      PlayerSocial.remove(target, :ignore, owner.guid)
      admission = DuelSystem.challenge_admission(owner.guid, target.guid, world)
      assert Duel.validate_admission(admission) == :ok
    end
  end

  defp assert_status(result, guid) do
    assert_receive {:"$gen_cast",
                    {:send_packet, %Message.SmsgFriendStatus{result: ^result, friend: %Friend{guid: ^guid}}}}
  end

  defp characters(_context) do
    owner = character("Alice", 1)
    target = character("Café", 1)
    enemy = character("Enemy", 2)
    Registry.register(owner.guid)

    for state <- [owner, target, enemy] do
      CharacterStore.put(state.character)
      area = state.character.internal.area
      :ets.insert(Exploration, {{:area, area}, %AreaTable{id: area, parent_area_table: 12, flags: 0x40}})
    end

    publish(owner.character)

    on_exit(fn ->
      for state <- [owner, target, enemy] do
        PartySystem.leave(state.guid)
        Presence.leave(state.character)
        :ets.delete(SocialStore, state.guid)
        :ets.delete(CharacterStore, state.guid)
        :ets.delete(Exploration, {:area, state.character.internal.area})
      end
    end)

    %{owner: owner, target: target, enemy: enemy}
  end

  defp character(prefix, race) do
    guid = System.unique_integer([:positive, :monotonic])

    character = %Character{
      id: guid,
      object: %Object{guid: guid},
      unit: %Unit{race: race, class: 8, level: 50, health: 100, max_health: 100},
      player: %Player{},
      internal: %Internal{name: "#{prefix}#{guid}", world: WorldRef.open(0), area: 700_000 + guid},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    %{guid: guid, character: character, ready: true}
  end

  defp publish(character) do
    Presence.enter(character, %{
      name: character.internal.name,
      race: character.unit.race,
      level: character.unit.level,
      class: character.unit.class
    })
  end
end
