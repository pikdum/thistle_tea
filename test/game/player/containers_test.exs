defmodule ThistleTea.Game.Player.ContainersTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Lock
  alias ThistleTea.Game.Entity.Data.Lock.Requirement
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Inventory.Batch
  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.BinaryUtils
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.CmsgOpenItem
  alias ThistleTea.Game.Network.Message.CmsgUseItem
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Opcodes
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.Player.Containers
  alias ThistleTea.Game.Player.Gathering
  alias ThistleTea.Game.Player.Looting
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.Spell.TargetCodec
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.Lock, as: LockLoader
  alias ThistleTea.Game.World.Loader.Loot, as: LootLoader

  @source 999_911
  @reward 999_912
  @lock 999_913
  @spell 999_914
  @key 999_915

  setup [:container]

  describe "CMSG_OPEN_ITEM" do
    test "dispatches native bag and slot fields through the container boundary", %{state: state, source: source} do
      opcode = Opcodes.get(:CMSG_OPEN_ITEM)
      assert Dispatch.implemented?(opcode)

      assert %CmsgOpenItem{bag: 255, slot: 23} =
               message = Dispatch.to_message(%Packet{opcode: opcode, payload: <<255, 23>>})

      opened = CmsgOpenItem.handle(message, state)
      assert opened.loot_guid == source.object.guid
      assert opened.loot_type == :container
      assert Item.loot_generated?(ItemStore.get(source.object.guid))
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgLootResponse{loot_type: 1, loot: %Loot{gold: 25}}}}
    end
  end

  describe "open/2 and loot lifecycle" do
    test "reopening retained contents never rerolls or auto-collects them", %{state: state, source: source} do
      opened = Containers.open(state, {255, 23})
      original = ItemStore.get(source.object.guid)
      closed = Looting.release(opened)
      assert Inventory.count_entry(closed.character.player, @reward, &ItemStore.get/1) == 0
      assert ItemStore.get(source.object.guid) == original
      :ets.insert(LootLoader, {{:item, @source}, []})
      restored = %{closed | character: CharacterStore.get(state.guid)}
      reopened = Containers.open(restored, {255, 23})
      assert ItemStore.get(source.object.guid) == original
      claimed = Looting.take_item(reopened, 0)
      assert Inventory.count_entry(claimed.character.player, @reward, &ItemStore.get/1) == 2
      assert Looting.take_item(claimed, 0).character.player == claimed.character.player
      money = Looting.take_money(claimed)
      assert money.character.player.coinage == 125
      assert Looting.take_money(money).character.player.coinage == 125
      assert ItemStore.get(source.object.guid)
      closed = Looting.release(money)
      assert closed.character.player.inv1 == 0
      assert ItemStore.get(source.object.guid) == nil
      assert CharacterStore.get(state.guid).player == closed.character.player
    end

    test "failed storage retains the reward until space becomes available", %{state: state, source: source} do
      fillers = for _ <- 2..16, do: ItemStore.create(%ItemTemplate{entry: 99}, owner: state.guid)

      fields =
        fillers |> Enum.with_index(2) |> Enum.map(fn {item, i} -> {String.to_atom("inv#{i}"), item.object.guid} end)

      state = %{state | character: %{state.character | player: struct!(state.character.player, fields)}}
      opened = Containers.open(state, {255, 23})
      assert Looting.take_item(opened, 0).character == opened.character
      assert [%Loot.Item{looted: false}] = Item.loot(ItemStore.get(source.object.guid)).items
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgInventoryChangeFailure{code: 50}}}

      {:ok, changes} =
        opened.character.player
        |> Batch.new()
        |> Batch.remove_item(hd(fillers).object.guid, 1)
        |> Inventory.plan(&ItemStore.get/1)

      claimed = opened |> InventoryUpdate.apply({:ok, changes}) |> Looting.take_item(0)
      assert Inventory.count_entry(claimed.character.player, @reward, &ItemStore.get/1) == 2
    end

    test "rejects locked, foreign, dead and remote-bank sources including direct loot", %{state: state, source: source} do
      locked = locked(source)
      ItemStore.put(locked)
      assert Containers.open(state, {255, 23}) == state
      assert Looting.open(state, source.object.guid) == state
      refute Item.loot_generated?(ItemStore.get(source.object.guid))
      ItemStore.put(%{source | item: %{source.item | owner: state.guid + 1}})
      assert Containers.open(state, {255, 23}) == state
      ItemStore.put(source)
      dead = %{state | character: %{state.character | unit: %{state.character.unit | health: 0}}}
      assert Containers.open(dead, {255, 23}) == dead

      banked = %{
        state
        | character: %{state.character | player: %{state.character.player | inv1: 0, bank1: source.object.guid}}
      }

      assert Containers.open(banked, {255, 39}) == banked
      refute Item.loot_generated?(ItemStore.get(source.object.guid))
    end

    test "claims revalidate ownership after an item disappears", %{state: state, source: source} do
      opened = Containers.open(state, {255, 23})
      ItemStore.delete(source.object.guid)
      assert Looting.take_item(opened, 0).character == opened.character
      assert Looting.take_money(opened).character == opened.character
      assert Looting.close_unavailable(opened).loot_guid == nil
    end
  end

  describe "item-targeted unlocking" do
    test "typed completion unlocks, awards one point and opens private loot", %{
      state: state,
      source: source,
      spell: spell
    } do
      ItemStore.put(locked(source))
      guid = source.object.guid
      cast = %Cast{spell: spell, targets: Target.item(guid), ends_at: 0}
      character = Casting.complete(state.character, cast, 1_000)
      opening = Enum.find(character.internal.events, &is_struct(&1, Effects.OpenLock))
      assert opening.target_guid == guid
      EventSink.emit(state.character, opening, Context.new(self()))
      assert_receive {:open_lock, ^guid, ^spell, nil, _events} = command
      assert {:noreply, opened} = PlayerServer.handle_info(command, state)
      assert Item.unlocked?(ItemStore.get(guid))
      assert opened.character.player.skills[633].value == 2
      assert opened.loot_guid == guid
      assert CharacterStore.get(state.guid).player.skills[633].value == 2
      assert Gathering.complete(opened, guid, spell, nil) == opened
      closed = Looting.release(opened)
      assert Containers.open(closed, {255, 23}).character.player.skills[633].value == 2
    end

    test "instant key spells consume their charge only when unlocking succeeds", %{state: state, source: source} do
      Entity.register(state.guid)
      ItemStore.put(locked(source))

      key =
        ItemStore.create(%ItemTemplate{entry: @key, spellid_1: @spell, spelltrigger_1: 0, spellcharges_1: -1},
          owner: state.guid
        )

      state = %{state | character: %{state.character | player: %{state.character.player | inv2: key.object.guid}}}
      spell = %Spell{id: @spell, cast_time_ms: 0, effects: [%Effect{type: :open_lock, misc_value: 1, base_points: 99}]}

      message = %CmsgUseItem{
        bag: 255,
        slot: 24,
        spell_count: 1,
        targets: TargetCodec.encode(Target.item(source.object.guid))
      }

      cast = CmsgUseItem.handle(message, state, fn @spell -> spell end)
      assert ItemStore.get(key.object.guid) == key
      assert_receive {:open_lock, _guid, ^spell, _key, _events} = command
      assert {:noreply, opened} = PlayerServer.handle_info(command, cast)
      assert ItemStore.get(key.object.guid) == nil
      assert Item.unlocked?(ItemStore.get(source.object.guid))
      assert opened.character.player.skills[633].value == 1
    end

    test "completion rejects changed skill, removed targets and death", %{state: state, source: source, spell: spell} do
      ItemStore.put(locked(source))
      assert Gathering.complete(state, source.object.guid, %{spell | reagents: [{@reward, 1}]}, nil) == state
      refute Item.unlocked?(ItemStore.get(source.object.guid))

      :ets.insert(
        LockLoader,
        {@lock, %Lock{id: @lock, requirements: [%Requirement{type: :skill, index: 1, skill: 100}]}}
      )

      assert Gathering.complete(state, source.object.guid, spell, nil) == state
      refute Item.unlocked?(ItemStore.get(source.object.guid))
      dead = %{state | character: %{state.character | unit: %{state.character.unit | health: 0}}}
      assert Gathering.complete(dead, source.object.guid, spell, nil) == dead
      ItemStore.delete(source.object.guid)
      assert Gathering.complete(state, source.object.guid, spell, nil) == state
    end
  end

  defp locked(source), do: %{source | internal: %{source.internal | template: %{Item.template(source) | lockid: @lock}}}

  defp container(_context) do
    owner = Guid.from_low_guid(:player, System.unique_integer([:positive, :monotonic]))

    source =
      ItemStore.create(%ItemTemplate{entry: @source, flags: 4, min_money_loot: 25, max_money_loot: 25}, owner: owner)

    :ets.insert(ItemLoader, {@reward, %ItemTemplate{entry: @reward, stackable: 20, display_id: 1}})

    :ets.insert(
      LootLoader,
      {{:item, @source}, [%{item: @reward, chance: 100.0, groupid: 0, mincount_or_ref: 2, maxcount: 2, condition: nil}]}
    )

    :ets.insert(LockLoader, {@lock, %Lock{id: @lock, requirements: [%Requirement{type: :skill, index: 1, skill: 1}]}})

    character = %Character{
      id: owner,
      object: %Object{guid: owner},
      unit: %Unit{health: 100, max_health: 100, level: 20, race: 1, class: 4},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{},
      player: %Player{inv1: source.object.guid, coinage: 100, skills: Skills.learn_rank(%{}, 633, 100)}
    }

    CharacterStore.put(character)

    on_exit(fn ->
      :ets.delete(ItemLoader, @reward)
      :ets.delete(LootLoader, {:item, @source})
      :ets.delete(LockLoader, @lock)
      :ets.delete(CharacterStore, owner)

      :ets.select_delete(ItemStore, [
        {{:_, :"$1"}, [{:==, {:map_get, :owner, {:map_get, :item, :"$1"}}, owner}], [true]}
      ])
    end)

    %{
      state: %State{ready: true, guid: owner, packed_guid: BinaryUtils.pack_guid(owner), character: character},
      source: source,
      spell: %Spell{id: @spell, effects: [%Effect{type: :open_lock, misc_value: 1, base_points: 24}]}
    }
  end
end
