defmodule ThistleTea.Game.Player.TalentResetTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.Talent
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Stats
  alias ThistleTea.Game.Entity.Logic.Talents, as: TalentLogic
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.TalentReset
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Gossip
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.Talent, as: TalentLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.PostOffice
  alias ThistleTea.Game.World.Presence
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  @talent 777_001
  @trained 777_002
  @dependent 777_003
  @ordinary 777_004
  @foreign 777_005
  @triggered 777_006
  @summon 777_007
  @reagent 777_008
  @trainer 777_009

  setup [:build_state]

  describe "confirm/2" do
    test "quotes without altering the allocation, money, or price history", %{state: state, trainer: trainer} do
      offered = TalentReset.confirm(state, trainer)
      assert offered.character == state.character
      assert offered.talent_reset_offer == %TalentReset.Offer{trainer_guid: trainer, cost: 10_000}
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgGossipComplete{}}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.MsgTalentWipeConfirm{trainer_guid: ^trainer, cost: 10_000}}}
    end

    test "requires a level-ten player and a nearby living trainer of their class", %{state: state, trainer: trainer} do
      for invalid <- [
            put_in(state.character.unit.level, 9),
            put_in(state.character.unit.class, 9),
            put_in(state.character.unit.health, 0),
            %{state | ready: false}
          ] do
        assert TalentReset.confirm(invalid, trainer).talent_reset_offer == nil
      end

      Metadata.update(trainer, %{alive?: false})
      assert TalentReset.confirm(state, trainer).talent_reset_offer == nil
      Metadata.update(trainer, %{alive?: true, npc_flags: 0})
      assert TalentReset.confirm(state, trainer).talent_reset_offer == nil
    end
  end

  describe "complete/2" do
    test "unequips a weapon whose talent proficiency is lost and retains its skill history", %{
      state: state,
      trainer: trainer
    } do
      {state, weapon} = with_weapon(state)
      completed = state |> TalentReset.confirm(trainer) |> TalentReset.complete(trainer)
      assert completed.character.player.mainhand == 0
      assert completed.character.player.inv1 == weapon.object.guid
      assert completed.character.player.visible_item_16_0 == 0
      refute Map.has_key?(completed.character.player.skills, 172)
      assert completed.character.internal.forgotten_skills[172].value == 245
      assert ItemStore.get(weapon.object.guid).item.owner == state.guid
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgSetProficiency{item_class: 2, subclass_mask: 0}}}
    end

    test "returns an unusable weapon by mail when all bags are full", %{state: state, trainer: trainer} do
      {state, weapon} = with_weapon(state)

      player =
        Enum.reduce(1..16, state.character.player, fn slot, player ->
          item = ItemStore.create(%ItemTemplate{entry: @reagent}, owner: state.guid)
          Map.replace!(player, :"inv#{slot}", item.object.guid)
        end)

      state = %{state | character: %{state.character | player: player}}
      completed = state |> TalentReset.confirm(trainer) |> TalentReset.complete(trainer)
      assert completed.character.player.mainhand == 0
      assert ItemStore.get(weapon.object.guid) == weapon
      assert Inventory.find_position(completed.character.player, weapon.object.guid, &ItemStore.get/1) == nil
      {token, [mail]} = PostOffice.open(state.guid)
      assert mail.item_guid == weapon.object.guid
      assert mail.sender == state.guid
      assert mail.stationery == 61
      PostOffice.acknowledge(state.guid, token, [mail.id])
      assert :ok = PostOffice.close(state.guid, token, [])
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgDestroyObject{guid: guid}}}
      assert guid == weapon.object.guid
    end

    test "charges once, refunds points, removes dependent buffs, and preserves other classes' spells", %{
      state: state,
      trainer: trainer
    } do
      assert state.character.unit.stamina == 30
      assert TalentLogic.spent_points(state.character) == 1
      assert TalentLogic.unspent(state.character) == 40
      completed = state |> TalentReset.confirm(trainer) |> TalentReset.complete(trainer)
      character = completed.character
      assert character.player.coinage == 90_000
      assert character.player.character_points1 == 41
      assert Enum.sort(character.internal.spells) == [@ordinary, @foreign, @summon]
      assert character.unit.stamina == 22
      assert Enum.map(character.unit.auras, & &1.spell.id) == [@ordinary]
      assert character.internal.casting == nil
      assert character.internal.talent_reset.multiplier == 1
      assert is_integer(character.internal.talent_reset.last_reset_at)
      assert CharacterStore.get(character.id).internal.talent_reset == character.internal.talent_reset
      assert TalentReset.complete(completed, trainer) == completed
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgRemovedSpell{spell_id: @trained}}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgRemovedSpell{spell_id: @dependent}}}
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgRemovedSpell{spell_id: @foreign}}}, 0
      assert_receive {:"$gen_cast", {:trigger_spell, 14_867, _owner, []}}
      assert TalentReset.confirm(completed, trainer).talent_reset_offer.cost == 50_000
    end

    test "insufficient money leaves talents, pets, and history untouched", %{state: state, trainer: trainer} do
      state =
        state
        |> put_in([Access.key(:character), Access.key(:player), Access.key(:coinage)], 9_999)
        |> with_pet(:hunter_pet)

      pet = Companion.active_guid(state.character)
      completed = state |> TalentReset.confirm(trainer) |> TalentReset.complete(trainer)
      assert completed.character == state.character
      assert Entity.online?(pet)
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgBuyFailed{error: :not_enough_money}}}
    end

    test "revalidates trainer distance and world and rejects unsolicited or mismatched replies", %{
      state: state,
      trainer: trainer
    } do
      assert TalentReset.complete(state, trainer) == state
      offered = TalentReset.confirm(state, trainer)
      assert TalentReset.complete(offered, trainer + 1) == state
      SpatialHash.update(:mobs, trainer, WorldRef.open(451), 5.01, 0.0, 0.0)
      assert TalentReset.complete(offered, trainer) == state
      SpatialHash.update(:mobs, trainer, WorldRef.instance(451, 1), 0.0, 0.0, 0.0)
      assert TalentReset.complete(offered, trainer) == state
    end

    test "reports an empty allocation without charging", %{state: state, trainer: trainer} do
      state = put_in(state.character.internal.spells, [@ordinary, @foreign])
      completed = state |> TalentReset.confirm(trainer) |> TalentReset.complete(trainer)
      assert completed.character == state.character
      assert_receive {:"$gen_cast", {:send_packet, %Message.MsgTalentWipeConfirm{trainer_guid: 0, cost: 0}}}
    end

    test "suspends a hunter pet with its final progression and removes its process and controls", %{
      state: state,
      trainer: trainer
    } do
      state = with_pet(state, :hunter_pet)
      pet = Companion.active_guid(state.character)
      completed = state |> TalentReset.confirm(trainer) |> TalentReset.complete(trainer)
      assert completed.character.unit.summon == 0
      assert completed.character.internal.companion.status == {:suspended, 69, @summon}
      assert completed.character.internal.companion.progress.training_points == 17
      refute Entity.online?(pet)
      assert World.position(pet) == nil
      assert Metadata.get(pet) == nil
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgPetSpells{pet_guid: 0}}}
    end

    test "dismisses a summoned demon and refunds its reagent without restoring it on login", %{
      state: state,
      trainer: trainer
    } do
      state = with_pet(state, :guardian)
      pet = Companion.active_guid(state.character)
      completed = state |> TalentReset.confirm(trainer) |> TalentReset.complete(trainer)
      assert completed.character.internal.companion.status == :none
      assert Inventory.count_entry(completed.character.player, @reagent, &ItemStore.get/1) == 1
      refute Entity.online?(pet)
      assert World.position(pet) == nil
      assert Metadata.get(pet) == nil
    end
  end

  defp with_pet(state, kind) do
    guid = Guid.runtime(:pet, 69)

    pet = %Mob{
      object: %Object{guid: guid, entry: 69},
      unit: %Unit{health: 100, max_health: 100, level: 49, power5: 800_000, pet_loyalty: 2, auras: []},
      movement_block: state.character.movement_block,
      internal: %Internal{
        world: state.character.internal.world,
        pet: %Pet{
          owner_guid: state.guid,
          kind: if(kind == :hunter_pet, do: :hunter, else: :summon),
          profile: :combat,
          training_points: 17
        },
        creature: %Creature{},
        spawn: %Spawn{temporary?: true},
        spellbook: %{}
      }
    }

    {:ok, _pid} = World.start_entity(pet)
    on_exit(fn -> World.stop_entity(guid) end)
    character = Companion.activate(state.character, kind, %EntityRef{guid: guid, entry: 69, spell_id: @summon})
    %{state | character: character}
  end

  defp with_weapon(state) do
    template = %ItemTemplate{
      entry: @reagent + 100,
      class: 2,
      subclass: 1,
      inventory_type: 17,
      delay: 3_000,
      dmg_min1: 50.0,
      dmg_max1: 60.0
    }

    cache(ItemLoader, [{template.entry, template}])
    weapon = ItemStore.create(template, owner: state.guid)

    spell = %Spell{
      id: @dependent,
      equipped_item_class: 2,
      equipped_item_subclass_mask: 2,
      effects: [%Effect{type: :proficiency}]
    }

    character = state.character
    skills = %{172 => %{value: 245, max: 250, range: :level, always_max?: false}}

    player =
      %{character.player | mainhand: weapon.object.guid, skills: skills} |> Inventory.sync_visible_item(15, weapon)

    character = %{
      character
      | player: player,
        internal: %{character.internal | spellbook: Map.put(character.internal.spellbook, @dependent, spell)}
    }

    {%{state | character: character}, weapon}
  end

  defp build_state(_context) do
    owner = System.unique_integer([:positive, :monotonic]) + 10_000_000
    trainer = Guid.from_low_guid(:mob, @trainer, owner)
    Entity.register(owner)
    Entity.register(trainer)
    cache(Gossip, [{{:trainer, @trainer}, %{type: 0, class: 3}}])
    cache(ItemLoader, [{@reagent, %ItemTemplate{entry: @reagent, stackable: 1}}])

    cache(TalentLoader, [
      {{:tabs, 3}, [777]},
      {{:talent, @talent}, %Talent{id: @talent, tab_id: 777, rank_spell_ids: [@trained]}},
      {{:by_spell, @trained}, {@talent, 777, 0}},
      {{:by_spell, @foreign}, {@talent + 1, 888, 0}},
      {{:dependent_spells, @trained}, [@dependent]},
      {{:triggered_spells, @trained}, [@triggered]}
    ])

    Metadata.put(trainer, %{alive?: true, npc_flags: 0x10})
    SpatialHash.update(:mobs, trainer, WorldRef.open(451), 2.0, 0.0, 0.0)
    spells = Map.new([@trained, @dependent, @ordinary, @foreign, @summon], &{&1, %Spell{id: &1}})
    spells = Map.put(spells, @summon, %Spell{id: @summon, reagents: [{@reagent, 1}]})

    auras =
      for {id, amount} <- [{@trained, 5}, {@triggered, 3}, {@ordinary, 2}],
          do: %Holder{spell: %Spell{id: id}, auras: [%Aura{type: :mod_stat, misc_value: 2, amount: amount}], stacks: 1}

    character = %Character{
      id: owner,
      account_id: 1,
      object: %Object{guid: owner},
      unit:
        Stats.recompute(%Unit{
          health: 100,
          class: 3,
          race: 4,
          level: 50,
          base_stamina: 20,
          base_health: 100,
          auras: auras
        }),
      player: %Player{coinage: 100_000},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{
        world: WorldRef.open(451),
        spells: Map.keys(spells),
        spellbook: spells,
        casting: %Cast{spell: spells[@trained]}
      }
    }

    Presence.enter(character, %{alive?: true, faction_template: 1})

    on_exit(fn ->
      Metadata.delete(trainer)
      Metadata.delete(owner)
      SpatialHash.remove(:mobs, trainer)
      SpatialHash.remove(:players, owner)
      :ets.delete(CharacterStore, owner)

      :ets.select_delete(ItemStore, [
        {{:_, :"$1"}, [{:==, {:map_get, :owner, {:map_get, :item, :"$1"}}, owner}], [true]}
      ])
    end)

    %{state: %State{ready: true, guid: owner, character: character}, trainer: trainer}
  end

  defp cache(table, entries) do
    previous = Enum.flat_map(entries, fn {key, _value} -> :ets.lookup(table, key) end)
    :ets.insert(table, entries)

    on_exit(fn ->
      Enum.each(entries, fn {key, _value} -> :ets.delete(table, key) end)
      :ets.insert(table, previous)
    end)
  end
end
