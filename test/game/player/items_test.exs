defmodule ThistleTea.Game.Player.ItemsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network.Message.SmsgInventoryChangeFailure
  alias ThistleTea.Game.Network.Message.SmsgItemPushResult
  alias ThistleTea.Game.Player.Items
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.Skill, as: SkillLoader

  @entry 987_950

  setup [:inventory]

  describe "reward/3" do
    test "delivers a partial reward through the owner and commits only the instances that fit", %{state: state} do
      state = fill_backpack(state, 1..14)
      {:ok, _value} = Entity.register(state.guid)
      effect = %Effects.GiveItem{target_guid: state.guid, item_id: @entry, count: 3, partial?: true}
      EventSink.emit(state.character, effect, Context.new(self()))
      assert_received {:reward_item, @entry, 3} = message
      assert {:noreply, rewarded} = PlayerServer.handle_info(message, state)
      assert Inventory.count_entry(rewarded.character.player, @entry, &ItemStore.get/1) == 2
      assert CharacterStore.get(state.guid).player == rewarded.character.player
      assert_received {:"$gen_cast", {:send_packet, %SmsgInventoryChangeFailure{code: 50}}}
      assert_received {:"$gen_cast", {:send_packet, %SmsgItemPushResult{count: 1, created: 1}}}
      assert_received {:"$gen_cast", {:send_packet, %SmsgItemPushResult{count: 1, created: 1}}}
      refute_received {:"$gen_cast", {:send_packet, %SmsgItemPushResult{}}}
    end

    test "reports full bags without overwriting inventory or inserting an orphan", %{state: state} do
      state = fill_backpack(state, 1..16)
      size = :ets.info(ItemStore, :size)
      assert Items.reward(state, @entry, 1) == state
      assert :ets.info(ItemStore, :size) == size
      assert_received {:"$gen_cast", {:send_packet, %SmsgInventoryChangeFailure{code: 50}}}
      refute_received {:"$gen_cast", {:send_packet, %SmsgItemPushResult{}}}
    end

    test "reports a banked unique item instead of silently dropping the death reward", %{state: state} do
      template = %ItemTemplate{entry: @entry, max_count: 1}
      :ets.insert(ItemLoader, {@entry, template})
      item = ItemStore.create(template, owner: state.guid)
      state = put_in(state.character.player.bank1, item.object.guid)
      size = :ets.info(ItemStore, :size)
      assert Items.reward(state, @entry, 1) == state
      assert :ets.info(ItemStore, :size) == size
      code = Inventory.error_code(:cant_carry_more_of_this)
      assert_received {:"$gen_cast", {:send_packet, %SmsgInventoryChangeFailure{code: ^code}}}
      refute_received {:"$gen_cast", {:send_packet, %SmsgItemPushResult{}}}
    end
  end

  defp fill_backpack(state, slots) do
    player =
      Enum.reduce(slots, state.character.player, fn slot, player ->
        item = ItemStore.create(%ItemTemplate{entry: @entry + 2}, owner: state.guid)
        struct!(player, [{:"inv#{slot}", item.object.guid}])
      end)

    %{state | character: %{state.character | player: player}}
  end

  describe "create/4" do
    setup [:recipe]

    test "carries the recipe through owner delivery and commits one gain for a product stack", %{state: state} do
      event = %{Effects.create_item(@entry, 5) | spell_id: @entry + 1}
      EventSink.emit(state.character, event, Context.new(self()))
      assert_received {:create_item, @entry, 5, recipe_id} = message
      assert recipe_id == @entry + 1
      assert {:noreply, created} = PlayerServer.handle_info(message, state)
      assert Inventory.count_entry(created.character.player, @entry, &ItemStore.get/1) == 5
      assert created.character.player.skills[599].value == 2
      assert created.character.player.skills[599].step == 1
      assert CharacterStore.get(state.guid).player.skills[599].value == 2
    end

    test "does not gain skill from ordinary grants, missing professions, capped skills, or unique limits", %{
      state: state
    } do
      plain = Items.create(state, @entry, 1)
      assert plain.character.player.skills[599].value == 1
      missing = %{state | character: %{state.character | player: %{state.character.player | skills: %{}}}}
      assert Items.create(missing, @entry, 1, @entry + 1).character.player.skills == %{}
      capped = put_in(state.character.player.skills[599].value, 75)
      assert Items.create(capped, @entry, 1, @entry + 1).character.player.skills[599].value == 75
      :ets.insert(ItemLoader, {@entry, %ItemTemplate{entry: @entry, max_count: 1}})
      assert Items.create(plain, @entry, 1, @entry + 1) == plain
    end

    test "leaves the skill unchanged when the complete product cannot fit", %{state: state} do
      player =
        Enum.reduce(1..16, state.character.player, fn slot, player ->
          item = ItemStore.create(%ItemTemplate{entry: @entry + 2}, owner: state.guid)
          Map.replace!(player, :"inv#{slot}", item.object.guid)
        end)

      state = %{state | character: %{state.character | player: player}}
      unchanged = Items.create(state, @entry, 1, @entry + 1)
      assert unchanged == state
      assert Inventory.count_entry(unchanged.character.player, @entry, &ItemStore.get/1) == 0
    end
  end

  describe "create/3" do
    test "silently preserves an existing unique item in the bank", %{state: state} do
      template = %ItemTemplate{entry: @entry, max_count: 1}
      :ets.insert(ItemLoader, {@entry, template})
      existing = ItemStore.create(template, owner: state.guid)
      state = put_in(state.character.player.bank1, existing.object.guid)
      size = :ets.info(ItemStore, :size)

      assert Items.create(state, @entry, 1) == state
      assert :ets.info(ItemStore, :size) == size
      refute_received {:"$gen_cast", {:send_packet, _}}
    end

    test "replaces a missing unique item once", %{state: state} do
      :ets.insert(ItemLoader, {@entry, %ItemTemplate{entry: @entry, max_count: 1}})
      created = Items.create(state, @entry, 1)
      assert Inventory.count_entry(created.character.player, @entry, &ItemStore.get/1) == 1
      assert Items.create(created, @entry, 1) == created
    end

    test "clamps spell-created stacks to the remaining unique allowance", %{state: state} do
      template = %ItemTemplate{entry: @entry, max_count: 5, stackable: 20}
      :ets.insert(ItemLoader, {@entry, template})
      existing = ItemStore.create(template, owner: state.guid, stack_count: 3)
      state = put_in(state.character.player.inv1, existing.object.guid)
      created = Items.create(state, @entry, 4)
      assert Inventory.count_entry(created.character.player, @entry, &ItemStore.get/1) == 5
    end
  end

  describe "store/3" do
    test "creates separate instances of non-stackable equipment", %{state: state} do
      assert {:ok, stored, {255, 23}} = Items.store(state, @entry, 2)
      items = Inventory.owned_items(stored.character.player, &ItemStore.get/1)
      assert Enum.map(items, & &1.item.stack_count) == [1, 1]
      assert length(Enum.uniq_by(items, & &1.object.guid)) == 2
    end

    test "splits large grants into legal stacks", %{state: state} do
      :ets.insert(ItemLoader, {@entry, %ItemTemplate{entry: @entry, stackable: 20}})
      assert {:ok, stored, _position} = Items.store(state, @entry, 45)

      assert Inventory.owned_items(stored.character.player, &ItemStore.get/1) |> Enum.map(& &1.item.stack_count) == [
               20,
               20,
               5
             ]
    end

    test "rolls back the entire grant when all instances cannot fit", %{state: state} do
      player =
        Enum.reduce(1..15, state.character.player, fn slot, player ->
          item = ItemStore.create(%ItemTemplate{entry: @entry + 1}, owner: state.guid)
          Map.replace!(player, :"inv#{slot}", item.object.guid)
        end)

      state = %{state | character: %{state.character | player: player}}
      size = :ets.info(ItemStore, :size)
      assert {:error, :inventory_full, ^state} = Items.store(state, @entry, 2)
      assert :ets.info(ItemStore, :size) == size
      assert Inventory.count_entry(player, @entry, &ItemStore.get/1) == 0
    end
  end

  describe "store_many/2" do
    test "commits all entries and legal stacks together", %{state: state} do
      :ets.insert(ItemLoader, {@entry, %ItemTemplate{entry: @entry, stackable: 2}})
      assert {:ok, stored} = Items.store_many(state, [{@entry, 3}, {@entry, 1}])
      assert Inventory.count_entry(stored.character.player, @entry, &ItemStore.get/1) == 4

      assert Inventory.owned_items(stored.character.player, &ItemStore.get/1) |> Enum.map(& &1.item.stack_count) == [
               2,
               2
             ]
    end

    test "does not grant an early entry when a later entry fails", %{state: state} do
      size = :ets.info(ItemStore, :size)
      assert {:error, :item_not_found, ^state} = Items.store_many(state, [{@entry, 1}, {@entry + 1, 1}])
      assert :ets.info(ItemStore, :size) == size
      assert Inventory.count_entry(state.character.player, @entry, &ItemStore.get/1) == 0
    end
  end

  defp recipe(%{state: state}) do
    keys = [{:category, 599}, {:spell_skills, @entry + 1}]
    previous = Enum.flat_map(keys, &:ets.lookup(SkillLoader, &1))

    :ets.insert(SkillLoader, [
      {{:category, 599}, 11},
      {{:spell_skills, @entry + 1},
       [
         %{skill_line: 599, trivial_skill_line_rank_low: 25, trivial_skill_line_rank_high: 70}
       ]}
    ])

    :ets.insert(ItemLoader, {@entry, %ItemTemplate{entry: @entry, stackable: 20}})

    on_exit(fn ->
      Enum.each(keys, &:ets.delete(SkillLoader, &1))
      :ets.insert(SkillLoader, previous)
    end)

    player = %{state.character.player | skills: Skills.learn_rank(%{}, 599, 75)}
    %{state: %{state | character: %{state.character | player: player}}}
  end

  defp inventory(_context) do
    ItemStore.init()
    ItemLoader.init()
    :ets.insert(ItemLoader, {@entry, %ItemTemplate{entry: @entry, stackable: 1}})

    character =
      CharacterStore.create(%Character{
        id: 0,
        object: %Object{guid: 0},
        player: %Player{},
        unit: %Unit{health: 100, max_health: 100, level: 10},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{}
      })

    guid = character.object.guid

    on_exit(fn ->
      :ets.delete(ItemLoader, @entry)
      :ets.delete(CharacterStore, character.id)

      :ets.select_delete(ItemStore, [{{:_, :"$1"}, [{:==, {:map_get, :owner, {:map_get, :item, :"$1"}}, guid}], [true]}])
    end)

    %{state: %State{guid: guid, character: character}}
  end
end
