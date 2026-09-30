defmodule ThistleTea.Game.Inbound.CmsgUseItemTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.ItemTemplate
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Inventory
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Cast
  alias ThistleTea.Game.Core.Spell.Casting
  alias ThistleTea.Game.Core.Spell.Cooldowns
  alias ThistleTea.Game.Core.Spell.Target
  alias ThistleTea.Game.Core.Spell.TargetCodec
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.Inbound.CmsgUseItem
  alias ThistleTea.Game.Network.BinaryUtils
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.Player.UsableItems
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.ItemTarget
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash

  @backpack_start 23
  @not_ready 0x3C
  @spell_id 430

  setup do
    ItemStore.init()
    :ok
  end

  describe "handle/3" do
    test "rejects invalid creature targets without charges or cooldowns and permits a corrected retry" do
      player_guid = Guid.from_low_guid(:player, unique_id())
      entry = unique_id() + 1_000_000
      target = Guid.from_low_guid(:mob, 7977, unique_id())
      template = %{drink_template() | entry: entry, stackable: 1, spellcharges_1: 3}
      item = ItemStore.create(template, owner: player_guid)
      :ets.insert(ItemTarget, {entry, [{7977, true}]})
      Metadata.put(target, %{entry: 7978, alive?: true, unit_flags: 0})
      SpatialHash.update(:mobs, target, %WorldRef{map_id: 0}, 1.0, 0.0, 0.0)

      on_exit(fn ->
        :ets.delete(ItemTarget, entry)
        ItemStore.delete(item.object.guid)
        Metadata.delete(target)
        SpatialHash.remove(:mobs, target)
      end)

      spell = %Spell{
        id: @spell_id,
        name: "Quest tool",
        cast_time_ms: 10_000,
        attributes: MapSet.new([:ignore_line_of_sight])
      }

      state = %{
        ready: true,
        guid: player_guid,
        packed_guid: BinaryUtils.pack_guid(player_guid),
        character: character(player_guid, item.object.guid),
        player_tick_ref: nil
      }

      message = %CmsgUseItem{
        bag: Inventory.bag_0(),
        slot: @backpack_start,
        targets: TargetCodec.encode(Target.unit(target))
      }

      for metadata <- [%{entry: 7978, alive?: true}, %{entry: 7977, alive?: false}] do
        Metadata.update(target, metadata)
        rejected = use_item(message, state, fn @spell_id -> spell end)
        assert rejected.character.internal.casting == nil
        assert rejected.character.internal.cooldowns == %{}
        assert ItemStore.get(item.object.guid) == item
        assert_received {:"$gen_cast", {:send_packet, %Message.SmsgCastResult{reason: 0x0A}}}
        assert_received {:"$gen_cast", {:send_packet, %Message.SmsgInventoryChangeFailure{code: 0}}}
      end

      Metadata.update(target, %{alive?: true})
      accepted = use_item(message, state, fn @spell_id -> spell end)
      assert %Cast{consume_item: true} = accepted.character.internal.casting
      assert ItemStore.get(item.object.guid) == item
    end

    test "instant transformation keeps its charged source until atomic replacement" do
      player_guid = Guid.from_low_guid(:player, unique_id())
      Entity.register(player_guid)

      spell = %Spell{
        id: @spell_id,
        cast_time_ms: 0,
        effects: [%Spell.Effect{type: :summon_change_item, misc_value: 21_174}]
      }

      item = ItemStore.create(%{drink_template() | stackable: 1}, owner: player_guid)
      on_exit(fn -> ItemStore.delete(item.object.guid) end)

      state =
        use_item(
          %CmsgUseItem{bag: Inventory.bag_0(), slot: @backpack_start, spell_count: 1, targets: <<0::little-size(16)>>},
          %{
            ready: true,
            guid: player_guid,
            packed_guid: BinaryUtils.pack_guid(player_guid),
            character: character(player_guid, item.object.guid),
            player_tick_ref: nil
          },
          fn @spell_id -> spell end
        )

      guid = item.object.guid
      assert ItemStore.get(guid) == item
      assert state.character.player.inv1 == guid
      assert_receive {:transform_item, ^guid, %Spell{id: @spell_id}, 21_174}
      refute_received {:consume_cast_item, _}
    end

    test "uses item cooldown overrides for on-use spells" do
      player_guid = Guid.from_low_guid(:player, unique_id())
      spell = %Spell{id: @spell_id, name: "Drink", cast_time_ms: 0, category: 59, category_recovery_time_ms: 60_000}
      item = ItemStore.create(drink_template(), owner: player_guid, stack_count: 2)
      started_at = Time.now()

      on_exit(fn -> ItemStore.delete(item.object.guid) end)

      state =
        use_item(
          %CmsgUseItem{bag: Inventory.bag_0(), slot: @backpack_start, spell_count: 1, targets: <<0::little-size(16)>>},
          %{
            ready: true,
            guid: player_guid,
            packed_guid: BinaryUtils.pack_guid(player_guid),
            character: character(player_guid, item.object.guid),
            player_tick_ref: nil
          },
          fn @spell_id -> spell end
        )

      ready_at = Cooldowns.ready_at(state.character, %{spell | category: 59})

      assert is_integer(ready_at)
      assert ready_at - started_at <= 1_250
      assert ItemStore.get(item.object.guid).item.stack_count == 1
    end

    test "defers consumption for cast-time spells until the cast completes" do
      player_guid = Guid.from_low_guid(:player, unique_id())
      spell = %Spell{id: @spell_id, name: "Symbol of Life", cast_time_ms: 10_000}
      item = ItemStore.create(drink_template(), owner: player_guid, stack_count: 2)

      on_exit(fn -> ItemStore.delete(item.object.guid) end)

      state =
        use_item(
          %CmsgUseItem{bag: Inventory.bag_0(), slot: @backpack_start, spell_count: 1, targets: <<0::little-size(16)>>},
          %{
            ready: true,
            guid: player_guid,
            packed_guid: BinaryUtils.pack_guid(player_guid),
            character: character(player_guid, item.object.guid),
            player_tick_ref: nil
          },
          fn @spell_id -> spell end
        )

      item_guid = item.object.guid

      assert ItemStore.get(item_guid).item.stack_count == 2
      assert %Cast{cast_item_guid: ^item_guid, consume_item: true} = state.character.internal.casting

      character = Casting.complete(state.character, Time.now() + 11_000)

      assert Enum.any?(character.internal.events, fn event ->
               is_struct(event, Effects.ConsumeCastItem) and event.cast_item_guid == item_guid
             end)
    end

    test "does not consume a charged item when its spell cast fails" do
      player_guid = Guid.from_low_guid(:player, unique_id())
      spell = %Spell{id: @spell_id, name: "Drink", cast_time_ms: 0, category: 59, category_recovery_time_ms: 60_000}
      item = ItemStore.create(drink_template(), owner: player_guid, stack_count: 2)

      on_exit(fn -> ItemStore.delete(item.object.guid) end)

      character =
        player_guid
        |> character(item.object.guid)
        |> Cooldowns.start(%Spell{id: @spell_id, category: 59, category_recovery_time_ms: 1_000}, Time.now())

      state =
        use_item(
          %CmsgUseItem{bag: Inventory.bag_0(), slot: @backpack_start, spell_count: 1, targets: <<0::little-size(16)>>},
          %{
            ready: true,
            guid: player_guid,
            packed_guid: BinaryUtils.pack_guid(player_guid),
            character: character,
            player_tick_ref: nil
          },
          fn @spell_id -> spell end
        )

      assert state.character.player.inv1 == item.object.guid
      assert ItemStore.get(item.object.guid).item.stack_count == 2

      assert_receive {:"$gen_cast",
                      {:send_packet, %Message.SmsgCastResult{spell: @spell_id, result: 2, reason: @not_ready}}}
    end
  end

  defp drink_template do
    %ItemTemplate{
      entry: 1_599,
      name: "Refreshing Spring Water",
      stackable: 20,
      spellid_1: @spell_id,
      spelltrigger_1: 0,
      spellcharges_1: -1,
      spellcooldown_1: 0,
      spellcategory_1: 59,
      spellcategorycooldown_1: 1_000
    }
  end

  defp character(player_guid, item_guid) do
    %Character{
      object: %Object{guid: player_guid},
      unit: %Unit{health: 100, max_health: 100, power1: 100, max_power1: 100, class: 1, race: 1, level: 10},
      player: %Player{inv1: item_guid},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: %WorldRef{map_id: 0}}
    }
  end

  defp unique_id do
    System.unique_integer([:positive, :monotonic])
  end

  defp use_item(%{bag: bag, slot: slot, targets: targets}, state, load_spell),
    do: UsableItems.use(state, {bag, slot}, targets, load_spell)
end
