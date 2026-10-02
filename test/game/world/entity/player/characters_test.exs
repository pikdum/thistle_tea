defmodule ThistleTea.Game.World.Entity.Player.CharactersTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.CreatureTemplate
  alias ThistleTea.Game.Core.Entity.ItemTemplate
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Guild.Member
  alias ThistleTea.Game.Core.Inventory
  alias ThistleTea.Game.Core.Mail
  alias ThistleTea.Game.Core.Pet.Companion
  alias ThistleTea.Game.Core.Pet.PetProgress
  alias ThistleTea.Game.Core.Social
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.Network.Message.SmsgCharEnum
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Entity.Player.Characters
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.CreatureTemplate, as: CreatureTemplateLoader
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.SocialStore
  alias ThistleTea.Game.World.System.Guild, as: GuildSystem
  alias ThistleTea.Game.World.System.PostOffice
  alias ThistleTea.Test.Unique

  setup do
    CharacterStore.init()
    ItemStore.init()
    ItemLoader.init()

    reset_counter_table(CharacterStore)
    reset_counter_table(ItemStore)
    :ets.delete_all_objects(ItemLoader)

    :ok
  end

  describe "create/1" do
    test "equips and stores playercreateinfo starting items" do
      cache_templates([
        template(25, inventory_type: 21, class: 2, subclass: 7, dmg_min1: 1.0, dmg_max1: 2.0),
        template(38, inventory_type: 4),
        template(39, inventory_type: 7),
        template(40, inventory_type: 8),
        template(117, inventory_type: 0, stackable: 20),
        template(2362, inventory_type: 14),
        template(6948, inventory_type: 0)
      ])

      assert {:ok, character} =
               Characters.create(
                 character(
                   "Starter",
                   [
                     %{item_id: 25, amount: 1},
                     %{item_id: 38, amount: 1},
                     %{item_id: 39, amount: 1},
                     %{item_id: 40, amount: 1},
                     %{item_id: 117, amount: 4},
                     %{item_id: 2362, amount: 1},
                     %{item_id: 6948, amount: 1}
                   ]
                 )
               )

      player = character.player

      assert ItemStore.get(player.mainhand).object.entry == 25
      assert ItemStore.get(player.body).object.entry == 38
      assert ItemStore.get(player.legs).object.entry == 39
      assert ItemStore.get(player.feet).object.entry == 40
      assert ItemStore.get(player.offhand).object.entry == 2362
      assert player.visible_item_16_0 == 25
      assert player.visible_item_17_0 == 2362
      assert Inventory.count_entry(player, 117, &ItemStore.get/1) == 4
      assert Inventory.count_entry(player, 6948, &ItemStore.get/1) == 1
      assert character.unit.health == character.unit.max_health
      assert character.unit.power1 == character.unit.max_power1
    end

    test "splits oversized starting quantities into legal item instances" do
      cache_templates([template(6265, []), template(117, stackable: 20)])
      assert {:ok, character} = Characters.create(character("Legalstacks", [{6265, 5}, {117, 45}]))
      items = Inventory.owned_items(character.player, &ItemStore.get/1)
      assert items |> Enum.filter(&(&1.object.entry == 6265)) |> Enum.map(& &1.item.stack_count) == [1, 1, 1, 1, 1]

      assert items |> Enum.filter(&(&1.object.entry == 117)) |> Enum.map(& &1.item.stack_count) |> Enum.sort() == [
               5,
               20,
               20
             ]

      refute_received {:"$gen_cast", {:send_packet, _packet}}
    end

    test "rejects an oversized starting grant atomically when its legal stacks cannot fit" do
      cache_templates([template(6265, [])])
      assert {:ok, character} = Characters.create(character("Nostackroom", [{6265, 17}]))
      assert Inventory.count_entry(character.player, 6265, &ItemStore.get/1) == 0
      assert :ets.tab2list(ItemStore) |> Enum.reject(fn {key, _value} -> key == :counter end) == []
    end

    test "ignores missing starting item templates" do
      cache_templates([template(6948, inventory_type: 0)])

      assert {:ok, character} =
               Characters.create(
                 character("Missingitem", [
                   %{item_id: 999_999, amount: 1},
                   %{item_id: 6948, amount: 1}
                 ]),
                 &ItemLoader.get_cached_template/1
               )

      assert Inventory.count_entry(character.player, 6948, &ItemStore.get/1) == 1
      assert Inventory.count_entry(character.player, 999_999, &ItemStore.get/1) == 0
    end

    test "persists placed item state after a partial starting stack merge" do
      cache_templates([template(117, inventory_type: 0, stackable: 20)])

      assert {:ok, character} =
               Characters.create(
                 character("Partialstack", [
                   %{item_id: 117, amount: 19},
                   %{item_id: 117, amount: 5}
                 ])
               )

      stacks =
        character.player
        |> Inventory.owned_items(&ItemStore.get/1)
        |> Enum.filter(&(&1.object.entry == 117))
        |> Enum.map(& &1.item.stack_count)
        |> Enum.sort()

      assert stacks == [4, 20]
      assert Inventory.count_entry(character.player, 117, &ItemStore.get/1) == 24
    end

    test "clears equipped starter gear before applying a debug gear set" do
      cache_templates([
        template(25, inventory_type: 21, class: 2, subclass: 7),
        template(8190, inventory_type: 13, class: 2, subclass: 7)
      ])

      assert {:ok, character} =
               Characters.create(
                 character("Bettergear", [
                   %{item_id: 25, amount: 1}
                 ])
               )

      character =
        character
        |> Characters.clear_equipment()
        |> Characters.assign_items([8190])

      assert ItemStore.get(character.player.mainhand).object.entry == 8190
      assert Inventory.count_entry(character.player, 25, &ItemStore.get/1) == 0
    end
  end

  describe "enum/1" do
    test "lists the account's characters with their pose and visible gear" do
      cache_templates([
        template(25, inventory_type: 21, class: 2, subclass: 7, dmg_min1: 1.0, dmg_max1: 2.0, display_id: 1542),
        template(38, inventory_type: 4, display_id: 9891)
      ])

      {:ok, character} =
        Characters.create(character("Lister", [%{item_id: 25, amount: 1}, %{item_id: 38, amount: 1}]))

      CharacterStore.put(%{
        character
        | movement_block: %MovementBlock{position: {1.0, 2.0, 3.0, 0.5}},
          internal: %{character.internal | world: WorldRef.open(0), area: 12}
      })

      assert %SmsgCharEnum{amount_of_characters: 1, characters: [entry]} = Characters.enum(1)
      assert {entry.name, entry.guid, entry.map, entry.area} == {"Lister", character.id, 0, 12}
      assert entry.position == {1.0, 2.0, 3.0}
      assert length(entry.equipment) == length(Inventory.slots())
      assert Enum.at(entry.equipment, Inventory.slot_index(:mainhand)).equipment_display_id == 1542
      assert Enum.at(entry.equipment, Inventory.slot_index(:body)).inventory_type == 4
      assert Enum.at(entry.equipment, Inventory.slot_index(:head)).equipment_display_id == 0
      assert %SmsgCharEnum{amount_of_characters: 0, characters: []} = Characters.enum(2)
    end

    test "projects hidden gear, ghost state, and the waiting pet" do
      entry = 900_000 + Unique.integer()
      :ets.insert(CreatureTemplateLoader, {entry, %CreatureTemplate{entry: entry, display_id: 903, family: 1}})
      on_exit(fn -> :ets.delete(CreatureTemplateLoader, entry) end)

      {:ok, character} = Characters.create(character("Packleader", []))

      character = %{
        character
        | movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
          internal: %{character.internal | world: WorldRef.open(0)}
      }

      pet = %Companion{kind: :hunter_pet, status: {:suspended, entry, 0}, progress: %PetProgress{level: 7}}

      CharacterStore.put(%{
        character
        | player: %{character.player | flags: 0xC00},
          internal: %{character.internal | companion: pet}
      })

      assert %SmsgCharEnum{characters: [entry_row]} = Characters.enum(1)

      assert {entry_row.flags, entry_row.pet_display_id, entry_row.pet_level, entry_row.pet_family} ==
               {0xC00, 903, 7, 1}

      CharacterStore.put(%{
        character
        | player: %{character.player | flags: 0x10},
          internal: %{character.internal | companion: pet}
      })

      assert %SmsgCharEnum{characters: [ghost]} = Characters.enum(1)
      assert {ghost.flags, ghost.pet_display_id} == {0x2000, 0}
    end
  end

  describe "delete/2" do
    test "forgets the character, its items, and its social row" do
      cache_templates([template(38, inventory_type: 4), template(117, stackable: 20)])
      {:ok, character} = Characters.create(character("Retiree", [{38, 1}, {117, 5}]))
      guid = character.object.guid
      item_guids = character.player |> Inventory.all_owned_items(&ItemStore.get/1) |> Enum.map(& &1.object.guid)
      {:ok, social} = Social.add(%Social{owner_guid: guid}, :friend, guid + 1)
      SocialStore.put(social)

      assert :ok = Characters.delete(1, guid)
      assert CharacterStore.get(character.id) == nil
      assert length(item_guids) == 2
      assert Enum.all?(item_guids, &(ItemStore.get(&1) == nil))
      assert SocialStore.get(guid) == %Social{owner_guid: guid}
      assert %SmsgCharEnum{amount_of_characters: 0} = Characters.enum(1)
    end

    test "refuses another account's character and a guild leader" do
      {:ok, character} = Characters.create(character("Guildlord", []))
      guid = character.object.guid
      member = %Member{guid: guid, name: "Guildlord", race: 1, class: 1, level: 1}
      {:ok, _group} = GuildSystem.create(member, "Retirement Home #{Unique.integer()}")
      on_exit(fn -> GuildSystem.disband(guid) end)

      assert {:error, :character_not_found} = Characters.delete(2, guid)
      assert {:error, :guild_leader} = Characters.delete(1, guid)
      assert %Character{} = CharacterStore.get(character.id)
    end

    test "returns cash-on-delivery attachments to their sender and drops the rest" do
      id = Unique.integer()
      guid = Guid.from_low_guid(:player, id)
      sender = Guid.from_low_guid(:player, Unique.integer())
      CharacterStore.put(%{character("Codvictim", []) | id: id, object: %Object{guid: guid}})
      cod_item = ItemStore.create(template(2589, stackable: 20), owner: sender)
      gift_item = ItemStore.create(template(2589, stackable: 20), owner: sender)

      {:ok, _cod} =
        PostOffice.post(%{sender: sender, receiver: guid, subject: "Linen", item_guid: cod_item.object.guid, cod: 50})

      {:ok, _gift} =
        PostOffice.post(%{sender: sender, receiver: guid, subject: "Gift", item_guid: gift_item.object.guid})

      {:ok, _hello} = PostOffice.post(%{sender: sender, receiver: guid, subject: "Hello"})

      assert :ok = Characters.delete(1, guid)

      {token, mailbox} = PostOffice.open(sender)
      on_exit(fn -> PostOffice.close(sender, token, []) end)
      assert [%Mail{subject: "Linen", item_guid: returned_guid, cod: 0, receiver: ^sender}] = mailbox
      assert returned_guid == cod_item.object.guid
      assert ItemStore.get(returned_guid).item.owner == sender
      assert ItemStore.get(gift_item.object.guid) == nil
      assert PostOffice.forfeit(guid) == []
    end
  end

  defp reset_counter_table(table) do
    :ets.delete_all_objects(table)
    :ets.insert(table, {:counter, 0})
  end

  defp cache_templates(templates) do
    Enum.each(templates, fn %ItemTemplate{entry: entry} = template ->
      :ets.insert(ItemLoader, {entry, template})
    end)
  end

  defp character(name, starting_items) do
    %Character{
      account_id: 1,
      object: %Object{},
      unit: %Unit{
        race: 1,
        class: 1,
        level: 1,
        health: 1,
        power1: 1,
        max_health: 50,
        max_power1: 20,
        strength: 10,
        agility: 10,
        stamina: 10,
        intellect: 10,
        spirit: 10,
        base_strength: 10,
        base_agility: 10,
        base_stamina: 10,
        base_intellect: 10,
        base_spirit: 10,
        base_health: 50,
        base_mana: 20,
        min_damage: 1.0,
        max_damage: 2.0,
        min_offhand_damage: 0.0,
        max_offhand_damage: 0.0,
        base_attack_time: 2000,
        offhand_attack_time: 2000
      },
      player: %Player{},
      internal: %Internal{name: name, starting_items: starting_items}
    }
  end

  defp template(entry, attrs) do
    struct(
      ItemTemplate,
      Keyword.merge(
        [
          entry: entry,
          allowable_class: -1,
          allowable_race: -1,
          stackable: 1,
          max_durability: 1
        ],
        attrs
      )
    )
  end
end
