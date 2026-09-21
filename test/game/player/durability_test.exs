defmodule ThistleTea.Game.Player.DurabilityTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemEnchantment
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.EffectResolver.Durability, as: Resolver
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.Player.DevCommands
  alias ThistleTea.Game.Player.Durability
  alias ThistleTea.Game.Player.Enchantments
  alias ThistleTea.Game.Player.SpiritHealer
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Durability, as: DurabilityLoader
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.ItemEnchantment, as: EnchantmentLoader
  alias ThistleTea.Game.World.Loader.MapTemplate
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  @entry 997_930
  @enchant 997_931
  @level 997_932

  setup [:equipped_character]

  describe "lose/5 and repair/3" do
    test "debug wear parses whitespace and rejects invalid percentages", %{state: state, item: item} do
      assert {:handled, worn} = DevCommands.run(state, ".debug durability  10  ")
      assert ItemStore.get(item.object.guid).item.durability == 45
      assert {:handled, ^worn} = DevCommands.run(worn, ".debug durability 101")
      assert {:handled, ^worn} = DevCommands.run(worn, ".debug durability nonsense")
    end

    test "broken enchanted weapons lose stats and procs, then regain them on repair", context do
      %{state: state, item: item, vendor: vendor} = context
      initial = state.character
      assert initial.unit.base_min_damage == 20
      assert initial.unit.max_health == 150
      assert length(Enchantments.weapon_procs(initial, :mainhand)) == 1

      broken = Durability.lose(state, :percent, 100, :equipped)
      assert ItemStore.get(item.object.guid).item.durability == 0
      assert broken.character.unit.base_min_damage == 1.0
      assert broken.character.unit.max_health == 120
      assert broken.character.player.broken_equipment == [:mainhand]
      assert broken.character.player.parry_percentage == 0.0
      assert broken.character.player.visible_item_16_0 == initial.player.visible_item_16_0
      assert Enchantments.weapon_procs(broken.character, :mainhand) == []
      assert Character.sync_equipment_stats(broken.character).unit.max_health == 120
      assert CharacterStore.get(state.guid).player.broken_equipment == [:mainhand]

      repaired = Durability.repair(broken, vendor, item.object.guid)
      assert repaired.character.unit.base_min_damage == 20
      assert repaired.character.unit.max_health == 150
      assert repaired.character.player.coinage == 500
      assert repaired.character.player.broken_equipment == []
      assert repaired.character.player.parry_percentage == 5.0
      assert length(Enchantments.weapon_procs(repaired.character, :mainhand)) == 1
      assert ItemStore.get(item.object.guid).item.durability == 50
      assert Durability.repair(repaired, vendor, 0) == repaired
    end

    test "a broken shield loses armor and block until repaired", %{state: state, vendor: vendor} do
      template = %ItemTemplate{
        entry: @entry + 10,
        class: 4,
        subclass: 6,
        inventory_type: 14,
        item_level: @level,
        quality: 1,
        max_durability: 50,
        armor: 100,
        block: 20
      }

      :ets.insert(ItemLoader, {template.entry, template})
      :ets.insert(DurabilityLoader, {{@level, 4, 6}, 10})
      item = ItemStore.create(template, owner: state.guid)

      on_exit(fn ->
        ItemStore.delete(item.object.guid)
        :ets.delete(ItemLoader, template.entry)
        :ets.delete(DurabilityLoader, {@level, 4, 6})
      end)

      character = %{state.character | player: Inventory.equip(state.character.player, :offhand, item)}
      character = Character.sync_equipment_stats(character)
      assert character.player.block_percentage == 5.0
      assert character.unit.equipment_bonuses.armor == 100
      broken = Durability.lose(%{state | character: character}, :percent, 100, :offhand)
      assert broken.character.player.block_percentage == 0.0
      assert broken.character.unit.equipment_bonuses.armor == 0
      repaired = Durability.repair(broken, vendor, item.object.guid)
      assert repaired.character.player.block_percentage == 5.0
      assert repaired.character.unit.equipment_bonuses.armor == 100
    end

    @tag :dbc_db
    test "item passives follow committed durability changes", %{state: state, item: item, vendor: vendor} do
      template = %{item.internal.template | spellid_1: 7598, spelltrigger_1: 1}
      ItemStore.put(%{item | internal: %{item.internal | template: template}})
      equipped = Character.sync_equipment_stats(state.character)
      assert equipped.player.crit_percentage == 2.0
      broken = Durability.lose(%{state | character: equipped}, :percent, 100, :equipped)
      assert broken.character.player.crit_percentage == 0.0
      assert CharacterStore.get(state.guid).player.crit_percentage == 0.0
      repaired = Durability.repair(broken, vendor, item.object.guid)
      assert repaired.character.player.crit_percentage == 2.0
      assert CharacterStore.get(state.guid).player.crit_percentage == 2.0
    end

    test "an unaffordable repair preserves damage and money", %{state: state, item: item, vendor: vendor} do
      state = Durability.lose(state, :percent, 100, :equipped)
      state = %{state | character: %{state.character | player: %{state.character.player | coinage: 499}}}
      assert Durability.repair(state, vendor, 0) == state
      assert ItemStore.get(item.object.guid).item.durability == 0
    end

    test "dispatch decodes and executes the build-5875 repair request", %{state: state, item: item, vendor: vendor} do
      state = Durability.lose(state, :points, 1, :mainhand)
      payload = <<vendor::little-size(64), item.object.guid::little-size(64)>>
      message = Dispatch.to_message(Packet.build(payload, 0x2A8))
      assert %Message.CmsgRepairItem{vendor_guid: ^vendor} = message
      repaired = Message.CmsgRepairItem.handle(message, state)
      assert repaired.character.player.coinage == 990
      assert ItemStore.get(item.object.guid).item.durability == 50
      assert Message.SmsgDurabilityDamageDeath.to_binary(%Message.SmsgDurabilityDamageDeath{}) == <<>>
    end
  end

  describe "valid_vendor?/2" do
    test "rejects distant, dead, unflagged, and other-world vendors", %{state: state, vendor: vendor} do
      assert Durability.valid_vendor?(state.character, vendor)
      Metadata.update(vendor, %{alive?: false})
      refute Durability.valid_vendor?(state.character, vendor)
      Metadata.update(vendor, %{alive?: true, npc_flags: 4})
      refute Durability.valid_vendor?(state.character, vendor)
      Metadata.update(vendor, %{npc_flags: 0x4004})
      SpatialHash.update(:mobs, vendor, WorldRef.open(0), 6.0, 0.0, 0.0)
      refute Durability.valid_vendor?(state.character, vendor)
      SpatialHash.update(:mobs, vendor, WorldRef.instance(0, 55), 2.0, 0.0, 0.0)
      refute Durability.valid_vendor?(state.character, vendor)
    end

    test "dead and ghost players cannot repair", %{state: state, vendor: vendor} do
      dead = %{state.character | unit: %{state.character.unit | health: 0}}
      refute Durability.valid_vendor?(dead, vendor)
      ghost = %{state.character | player: %{state.character.player | flags: 0x10}}
      refute Durability.valid_vendor?(ghost, vendor)
      assert Durability.repair(%{state | ready: false}, vendor, 0) == %{state | ready: false}
    end
  end

  describe "death and combat wear" do
    test "spirit healing requires a ghost and a nearby healer in the same world", %{state: state, vendor: vendor} do
      ghost = %{state.character | player: %{state.character.player | flags: 0x10}}
      refute SpiritHealer.valid_healer?(ghost, vendor)
      Metadata.update(vendor, %{npc_flags: 0x20})
      assert SpiritHealer.valid_healer?(ghost, vendor)
      refute SpiritHealer.valid_healer?(state.character, vendor)
      assert SpiritHealer.activate(state, vendor) == state
      SpatialHash.update(:mobs, vendor, WorldRef.open(0), 6.0, 0.0, 0.0)
      refute SpiritHealer.valid_healer?(ghost, vendor)
      SpatialHash.update(:mobs, vendor, WorldRef.open(1), 2.0, 0.0, 0.0)
      refute SpiritHealer.valid_healer?(ghost, vendor)
    end

    test "one lethal transition wears equipment once and resurrection permits the next penalty", context do
      %{state: state, item: item, vendor: creature} = context
      dead = Core.take_damage(state.character, 1000, 1000, source: creature)
      assert [%Effects.DurabilityDamage{lethal?: true}] = wear_events(dead)
      repeated = Core.take_damage(%{dead | internal: %{dead.internal | events: []}}, 1000, 1001, source: creature)
      assert wear_events(repeated) == []

      dead = EventSink.emit_pending(dead, Context.new(self()))
      assert_receive {:durability_loss, :percent, 10, :equipped, true} = message
      assert {:noreply, worn, _continue} = PlayerServer.handle_info(message, %{state | character: dead})
      assert ItemStore.get(item.object.guid).item.durability == 45
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgDurabilityDamageDeath{}}}
      {alive, _events} = Death.resurrect(worn.character, 1.0, 2000)
      dead = Core.take_damage(alive, 1000, 3000, environmental?: true)
      assert [%Effects.DurabilityDamage{lethal?: true, environmental?: true}] = wear_events(dead)
    end

    test "PvP, controlled pets, battlegrounds, and exempt spells avoid death penalties", %{state: state, vendor: pet} do
      effect = %Effects.DurabilityDamage{source_guid: 123, lethal?: true, environmental?: false}
      assert Resolver.resolve(state.character, effect) == []
      Metadata.update(pet, %{owner_guid: 123})
      assert Resolver.resolve(state.character, %{effect | source_guid: pet}) == []
      :ets.insert(MapTemplate, {@level, 3})
      on_exit(fn -> :ets.delete(MapTemplate, @level) end)
      battleground = %{state.character | internal: %{state.character.internal | world: WorldRef.instance(@level, 1)}}
      assert Resolver.resolve(battleground, %{effect | source_guid: nil, environmental?: true}) == []
      spell = %Spell{id: 100, attributes: MapSet.new([:no_durability_loss])}
      dead = Core.take_damage(state.character, 1000, 1000, source: pet, spell: spell)
      assert wear_events(dead) == []
    end

    test "nonlethal combat rolls independently for attacker and victim", %{state: state, vendor: creature} do
      effect = %Effects.DurabilityDamage{source_guid: 123, lethal?: false, environmental?: false}
      opts = [roll: fn -> 0.1 end, slot: fn -> :mainhand end]

      assert [%Effects.DurabilityLoss{target_guid: victim}, %Effects.DurabilityLoss{target_guid: 123}] =
               Resolver.resolve(state.character, effect, opts)

      assert victim == state.guid
      assert [%Effects.DurabilityLoss{}] = Resolver.resolve(state.character, %{effect | source_guid: creature}, opts)
      assert Resolver.resolve(state.character, effect, roll: fn -> 0.5 end) == []
      assert Resolver.resolve(state.character, %{effect | environmental?: true}, opts) == []
      assert Resolver.resolve(state.character, %{effect | source_guid: state.guid}, opts) == []
    end

    test "absorbed and nonlethal environmental damage do not wear gear", %{state: state} do
      entity = Core.take_damage(state.character, 1, 1000, environmental?: true)
      assert wear_events(entity) == []
      entity = Core.take_damage(state.character, 0, 1000, source: 123)
      assert wear_events(entity) == []
      protected = %{state.character | internal: %{state.character.internal | godmode: true}}
      assert Core.take_damage(protected, 1000, 1000, source: 123) == protected
    end
  end

  defp wear_events(entity), do: Enum.filter(entity.internal.events, &is_struct(&1, Effects.DurabilityDamage))

  defp equipped_character(_context) do
    guid = System.unique_integer([:positive, :monotonic])
    vendor = Guid.from_low_guid(:mob, 54, guid)

    template = %ItemTemplate{
      entry: @entry,
      class: 2,
      subclass: 7,
      inventory_type: 13,
      item_level: @level,
      quality: 1,
      max_durability: 50,
      dmg_min1: 20,
      dmg_max1: 30,
      delay: 2500,
      stat_type1: 7,
      stat_value1: 1
    }

    :ets.insert(ItemLoader, {@entry, template})
    :ets.insert(DurabilityLoader, [{{@level, 2, 7}, 10}, {{:quality, 4}, 1.0}])

    enchant = %ItemEnchantment{
      id: @enchant,
      effects: [%{type: 5, spell_id: 1, amount: 20}, %{type: 1, spell_id: 0, amount: 10}]
    }

    :ets.insert(EnchantmentLoader, {{:enchantment, @enchant}, enchant})
    item = ItemStore.create(template, owner: guid) |> Item.put_permanent_enchantment(@enchant)
    ItemStore.put(item)
    player = Inventory.equip(%Player{coinage: 1000}, :mainhand, item)

    character =
      %Character{
        id: guid,
        object: %Object{guid: guid},
        player: player,
        internal: %Internal{
          spellbook: %{
            107 => %Spell{id: 107, effects: [%Effect{type: :block}]},
            3127 => %Spell{id: 3127, effects: [%Effect{type: :parry}]}
          }
        },
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        unit: %Unit{health: 100, max_health: 100, base_health: 100, base_stamina: 20, level: 10, class: 1, auras: []}
      }
      |> Character.sync_equipment_stats()

    {:ok, _} = Entity.register(guid)
    Metadata.put(vendor, %{alive?: true, npc_flags: 0x4004})
    SpatialHash.update(:mobs, vendor, WorldRef.open(0), 2.0, 0.0, 0.0)
    SpatialHash.update(:players, guid, WorldRef.open(0), 0.0, 0.0, 0.0)

    on_exit(fn ->
      ItemStore.delete(item.object.guid)
      :ets.delete(ItemLoader, @entry)
      :ets.delete(EnchantmentLoader, {:enchantment, @enchant})
      :ets.delete(DurabilityLoader, {@level, 2, 7})
      :ets.delete(DurabilityLoader, {:quality, 4})
      :ets.delete(CharacterStore, guid)
      Metadata.delete(vendor)
      Metadata.delete(guid)
      SpatialHash.remove(:mobs, vendor)
      SpatialHash.remove(:players, guid)
    end)

    %{state: %State{ready: true, guid: guid, character: character}, item: item, vendor: vendor}
  end
end
