defmodule ThistleTea.Game.Network.Message.CmsgUseItemTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.BinaryUtils
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.CmsgUseItem
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cooldowns
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.ItemStore

  @backpack_start 23
  @not_ready 0x3C
  @spell_id 430

  setup do
    ItemStore.init()
    :ok
  end

  describe "handle/3" do
    test "does not consume a charged item when its spell cast fails" do
      player_guid = Guid.from_low_guid(:player, unique_id())
      spell = %Spell{id: @spell_id, name: "Drink", recovery_time_ms: 60_000}
      item = ItemStore.create(drink_template(), owner: player_guid, stack_count: 2)

      on_exit(fn -> ItemStore.delete(item.object.guid) end)

      character =
        player_guid
        |> character(item.object.guid)
        |> Cooldowns.start(spell, Time.now())

      state =
        CmsgUseItem.handle(
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
      spellcharges_1: -1
    }
  end

  defp character(player_guid, item_guid) do
    %Character{
      object: %Object{guid: player_guid},
      unit: %Unit{health: 100, max_health: 100, power1: 100, max_power1: 100, class: 1, race: 1, level: 10},
      player: %Player{inv1: item_guid},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{map: 0}
    }
  end

  defp unique_id do
    System.unique_integer([:positive, :monotonic])
  end
end
