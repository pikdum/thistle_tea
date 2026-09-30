defmodule ThistleTea.Game.World.Entity.Player.AmmunitionTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.AI.BT.Ranged
  alias ThistleTea.Game.Core.Combat.AttackTimers
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Item
  alias ThistleTea.Game.Core.Entity.ItemTemplate
  alias ThistleTea.Game.Core.Inventory
  alias ThistleTea.Game.Core.Inventory.ChangeSet
  alias ThistleTea.Game.Core.Item.Ammunition, as: Ammo
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.Casting
  alias ThistleTea.Game.Core.Spell.Target
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.Inbound
  alias ThistleTea.Game.Inbound.Dispatch
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.EventSink
  alias ThistleTea.Game.World.Entity.Player.Ammunition
  alias ThistleTea.Game.World.Entity.Player.Equipment
  alias ThistleTea.Game.World.Entity.Player.State
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash

  setup [:armed_character]

  describe "select/2" do
    test "dispatch selects ammunition, recomputes damage, and saves the choice", %{state: state, arrows: arrows} do
      message = Dispatch.to_message(Packet.build(<<arrows.object.entry::little-size(32)>>, 0x268))
      assert %Inbound.CmsgSetAmmo{} = message
      selected = Inbound.handle(message, state)
      assert selected.character.player.ammo_id == arrows.object.entry
      assert selected.character.unit.base_ranged_min_damage == 30.0
      assert ItemStore.get(arrows.object.guid).item.stack_count == 2
      assert CharacterStore.get(state.guid).player.ammo_id == arrows.object.entry

      cleared = Ammunition.select(selected, 0)
      assert cleared.character.player.ammo_id == 0
      assert cleared.character.unit.base_ranged_min_damage == 20.0
      assert CharacterStore.get(state.guid).player.ammo_id == 0
    end

    test "rejects absent, banked, non-ammo, and unusable items", %{state: state, arrows: arrows, bow: bow} do
      assert Ammunition.select(state, 1) == state
      assert_failure(:item_not_found)
      assert Ammunition.select(state, bow.object.entry) == state
      assert_failure(:only_ammo_can_go_here)

      banked = %{
        state
        | character: %{state.character | player: %{state.character.player | inv1: nil, bank1: arrows.object.guid}}
      }

      assert Ammunition.select(banked, arrows.object.entry) == banked
      assert_failure(:item_not_found)

      for {field, value, reason} <- [
            {:required_level, 60, :cant_equip_level_i},
            {:allowable_class, 1, :you_can_never_use_that_item},
            {:required_skill, 999, :no_required_proficiency}
          ] do
        template = struct(Item.template(arrows), [{field, value}, {:required_skill_rank, 1}])
        ItemStore.put(%{arrows | internal: %{arrows.internal | template: template}})
        assert Ammunition.select(state, arrows.object.entry) == state
        assert_failure(reason)
      end
    end

    test "rejects selection and clearing while dead", %{state: state, arrows: arrows} do
      state = %{state | character: %{state.character | unit: %{state.character.unit | health: 0}}}

      for entry <- [arrows.object.entry, 0] do
        assert Ammunition.select(state, entry) == state
        assert_failure(:you_are_dead)
      end
    end
  end

  describe "launch/2" do
    test "a combat ranged swap invalidates a queued launch without spending ammunition", %{
      state: state,
      arrows: arrows,
      bow: bow,
      spell: spell
    } do
      state = Ammunition.select(state, arrows.object.entry)
      {state, request} = repeat(state, spell, 2_000)
      replacement = create_item(%{Item.template(bow) | entry: 997_984, delay: 3_500}, state.guid)
      previous = %{state.character | internal: %{state.character.internal | in_combat: true}}

      character =
        %{previous | player: Inventory.equip(previous.player, :ranged, replacement)} |> Equipment.sync_stats()

      character = AttackTimers.equipment_changed(character, previous, 2_000)
      replaced = %{state | character: character}

      assert character.internal.ranged_attack_at == 5_500
      assert character.internal.auto_shot.next_at == 5_500
      assert Ammunition.launch(replaced, request) == replaced
      assert ItemStore.get(arrows.object.guid).item.stack_count == 2
      refute_received {:"$gen_cast", {:receive_spell, _, _}}

      {replaced, fresh} = repeat(replaced, spell, 5_500)
      fired = Ammunition.launch(replaced, fresh)
      assert ItemStore.get(arrows.object.guid).item.stack_count == 1
      assert fired.character.internal.ranged_attack_at == 9_000
      assert_receive {:"$gen_cast", {:receive_spell, %CastContext{}, ^spell}}
    end

    test "wand repeats use the equipped school and skill without consuming ammunition", context do
      %{state: state, arrows: arrows} = context
      {state, spell, wand} = wand_weapon(state)
      {state, request} = repeat(state, spell, 2_000)
      fired = Ammunition.launch(state, request)

      assert_receive {:"$gen_cast", {:receive_spell, cast, delivered}}
      assert delivered.school == 6
      assert cast.spell == delivered
      assert cast.attack_power == 0
      assert cast.attack_skill == 217
      assert cast.weapon_skill_id == 228
      assert cast.weapon_base_min == 20.0
      assert ItemStore.get(wand.object.guid).item.durability == 50
      assert ItemStore.get(arrows.object.guid).item.stack_count == 2
      assert Ammunition.launch(fired, request) == fired
      refute_received {:"$gen_cast", {:receive_spell, _, _}}
    end

    test "queued wand shots recheck movement, broken gear, and weapon replacement", %{state: state, bow: bow} do
      {state, spell, wand} = wand_weapon(state)
      {state, request} = repeat(state, spell, 2_000)
      moving = %{state.character | movement_block: %{state.character.movement_block | movement_flags: 1}}
      assert Ammunition.launch(%{state | character: moving}, request).character.internal.auto_shot == nil
      refute_received {:"$gen_cast", {:receive_spell, _, _}}

      ItemStore.put(%{wand | item: %{wand.item | durability: 0}})
      assert Ammunition.launch(state, request).character.internal.auto_shot == nil
      refute_received {:"$gen_cast", {:receive_spell, _, _}}

      character = %{state.character | player: Inventory.equip(state.character.player, :ranged, bow)}
      assert Ammunition.launch(%{state | character: character}, request).character.internal.auto_shot == nil
      refute_received {:"$gen_cast", {:receive_spell, _, _}}
    end

    test "two arrows pay for exactly two repeats and depletion cancels without another projectile", context do
      %{state: state, arrows: arrows, spell: spell} = context
      state = Ammunition.select(state, arrows.object.entry)

      state =
        Enum.reduce(1..2, state, fn index, state ->
          {state, request} = repeat(state, spell, index * 2_000)
          fired = Ammunition.launch(state, request)
          assert_receive {:"$gen_cast", {:receive_spell, %CastContext{weapon_base_min: 30.0}, ^spell}}
          assert Inventory.count_entry(fired.character.player, arrows.object.entry, &ItemStore.get/1) == 2 - index
          assert Ammunition.launch(fired, request) == fired
          refute_received {:"$gen_cast", {:receive_spell, _, _}}
          fired
        end)

      {state, request} = repeat(state, spell, 6_000)
      exhausted = Ammunition.launch(state, request)
      assert exhausted.character.internal.auto_shot == nil
      assert exhausted.character.player.ammo_id == arrows.object.entry
      assert CharacterStore.get(state.guid).player.ammo_id == arrows.object.entry
      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgCastResult{reason: 0x43}}}
      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgCancelAutoRepeat{}}}
      refute_received {:"$gen_cast", {:receive_spell, _, _}}
    end

    test "canceled repeats and casts cannot spend items later", %{state: state, arrows: arrows, spell: spell} do
      state = Ammunition.select(state, arrows.object.entry)
      {state, request} = repeat(state, spell, 2_000)
      state = %{state | character: Ranged.stop(state.character)}
      assert Ammunition.launch(state, request) == state

      character = state.character |> Casting.start(spell, Target.self(state.guid), 0) |> Casting.complete(1_000)
      assert %Effects.LaunchRanged{kind: :cast} = request = List.last(character.internal.events)
      state = %{state | character: Casting.cancel(character, 1_000)}
      assert Ammunition.launch(state, request) == state
      assert ItemStore.get(arrows.object.guid).item.stack_count == 2
    end

    test "cast completion rechecks ammunition before spending mana or sending spell go", context do
      %{state: state, arrows: arrows, spell: spell} = context
      state = Ammunition.select(state, arrows.object.entry)
      spell = %{spell | cast_time_ms: 1_000, mana_cost: 10, power_type: 0}
      character = state.character |> Casting.start(spell, Target.self(state.guid), 0) |> Casting.complete(1_000)
      assert character.unit.power1 == 100
      refute Enum.any?(character.internal.events, &is_struct(&1, Effects.SpellGo))
      character = EventSink.emit_pending(character)
      assert_receive {:launch_ranged, request}
      ItemStore.delete(arrows.object.guid)
      failed = Ammunition.launch(%{state | character: character}, request)
      assert failed.character.internal.casting == nil
      assert failed.character.unit.power1 == 100
      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgCastResult{reason: 0x43}}}
      refute_received {:"$gen_cast", {:send_packet, %Message.SmsgSpellGo{}}}
    end

    test "successful cast launches once and pays exactly one arrow", %{state: state, arrows: arrows, spell: spell} do
      state = Ammunition.select(state, arrows.object.entry)
      character = state.character |> Casting.start(spell, Target.self(state.guid), 0) |> Casting.complete(1_000)
      character = EventSink.emit_pending(character)
      assert_receive {:launch_ranged, request}
      fired = Ammunition.launch(%{state | character: character}, request)
      assert fired.character.internal.casting == nil
      assert ItemStore.get(arrows.object.guid).item.stack_count == 1
      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgSpellGo{ammo_display_id: 5996}}}
      assert Ammunition.launch(fired, request) == fired
    end

    test "the final thrown weapon retains damage and its projectile before removal", context do
      %{state: state, spell: spell} = context
      {state, thrown} = thrown_weapon(state, 200, 0)
      {state, request} = repeat(state, spell, 2_000)
      fired = Ammunition.launch(state, request)
      assert_receive {:"$gen_cast", {:receive_spell, %CastContext{weapon_base_min: 20.0}, ^spell}}

      assert_received {:"$gen_cast",
                       {:send_packet, %Message.SmsgSpellGo{ammo_display_id: 256, ammo_inventory_type: 25}}}

      assert ItemStore.get(thrown.object.guid) == nil
      assert fired.character.player.ranged in [nil, 0]
      assert fired.character.unit.min_ranged_damage == 0
      {fired, request} = repeat(fired, spell, 4_000)
      failed = Ammunition.launch(fired, request)
      assert failed.character.internal.auto_shot == nil
      refute_received {:"$gen_cast", {:receive_spell, _, _}}
    end

    test "nonstacking thrown weapons spend durability without consuming selected arrows", context do
      %{state: state, arrows: arrows, spell: spell} = context
      state = Ammunition.select(state, arrows.object.entry)
      {state, thrown} = thrown_weapon(state, 1, 1)
      {state, request} = repeat(state, spell, 2_000)
      fired = Ammunition.launch(state, request)
      assert ItemStore.get(thrown.object.guid).item.durability == 0
      assert ItemStore.get(arrows.object.guid).item.stack_count == 2
      assert :ranged in fired.character.player.broken_equipment
      assert_receive {:"$gen_cast", {:receive_spell, %CastContext{weapon_base_min: 20.0}, ^spell}}
      {fired, request} = repeat(fired, spell, 4_000)
      assert Ammunition.launch(fired, request).character.internal.auto_shot == nil
      refute_received {:"$gen_cast", {:receive_spell, _, _}}
    end
  end

  describe "plan/3" do
    test "requires matching carried ammo and an unbroken weapon", %{state: state, arrows: arrows, spell: spell} do
      character = %{state.character | player: %{state.character.player | ammo_id: arrows.object.entry}}
      assert {:ok, _} = Ammo.plan(character, spell, &ItemStore.get/1)
      template = %{Item.template(arrows) | subclass: 3}
      ItemStore.put(%{arrows | internal: %{arrows.internal | template: template}})
      assert {:error, :no_ammo} = Ammo.plan(character, spell, &ItemStore.get/1)

      assert {:error, :equipped_item} =
               Ammo.plan(%{character | player: %{character.player | ranged: nil}}, spell, &ItemStore.get/1)
    end

    test "wands, non-ranged spells, and ranged exceptions spend no ammunition", %{
      state: state,
      bow: bow,
      arrows: arrows,
      spell: spell
    } do
      template = %{Item.template(bow) | subclass: 19, inventory_type: 26, ammo_type: 0}
      ItemStore.put(%{bow | internal: %{bow.internal | template: template}})
      character = %{state.character | player: %{state.character.player | ammo_id: arrows.object.entry}}

      for spell <- [spell, %{spell | dmg_class: 1}] ++ Enum.map([2094, 13_099, 13_119, 23_577], &%{spell | id: &1}) do
        assert {:ok, %ChangeSet{changed: changed, destroyed: destroyed}} = Ammo.plan(character, spell, &ItemStore.get/1)
        assert changed == %{}
        assert destroyed == %{}
      end
    end
  end

  defp assert_failure(reason) do
    code = Inventory.error_code(reason)
    assert_received {:"$gen_cast", {:send_packet, %Message.SmsgInventoryChangeFailure{code: ^code}}}
  end

  defp repeat(state, spell, now) do
    shot = %{
      spell: spell,
      target_guid: state.guid + 1,
      targets: Target.unit(state.guid + 1),
      next_at: now,
      pending?: true
    }

    state = %{state | character: %{state.character | internal: %{state.character.internal | auto_shot: shot}}}
    {state, %Effects.LaunchRanged{kind: :repeat, request: shot, now: now}}
  end

  defp thrown_weapon(state, stackable, durability) do
    template = %ItemTemplate{
      entry: 997_983,
      class: 2,
      subclass: 16,
      inventory_type: 25,
      stackable: stackable,
      max_durability: durability,
      dmg_min1: 20.0,
      dmg_max1: 30.0,
      delay: 2000,
      display_id: 256
    }

    thrown = create_item(template, state.guid)
    character = %{state.character | player: Inventory.equip(state.character.player, :ranged, thrown)}
    {%{state | character: Equipment.sync_stats(character)}, thrown}
  end

  defp wand_weapon(state) do
    template = %ItemTemplate{
      entry: 997_984,
      class: 2,
      subclass: 19,
      inventory_type: 26,
      dmg_type1: 6,
      dmg_min1: 20.0,
      dmg_max1: 30.0,
      delay: 1_500,
      max_durability: 50
    }

    wand = create_item(template, state.guid)
    player = state.character.player |> Inventory.equip(:ranged, wand) |> then(&%{&1 | skills: %{228 => %{value: 217}}})
    character = Equipment.sync_stats(%{state.character | player: player})

    spell = %Spell{
      id: 5019,
      dmg_class: 1,
      school: :physical,
      equipped_item_class: 2,
      equipped_item_subclass_mask: 524_288,
      attributes: MapSet.new([:auto_repeat, :uses_ranged_slot, :ignore_line_of_sight])
    }

    {%{state | character: character}, spell, wand}
  end

  defp create_item(template, owner, count \\ 1) do
    :ets.insert(ItemLoader, {template.entry, template})
    item = ItemStore.create(template, owner: owner, stack_count: count)

    on_exit(fn ->
      ItemStore.delete(item.object.guid)
      :ets.delete(ItemLoader, template.entry)
    end)

    item
  end

  defp armed_character(_context) do
    guid = System.unique_integer([:positive, :monotonic]) * 2
    {:ok, _} = Entity.register(guid)
    {:ok, _} = Entity.register(guid + 1)

    bow =
      create_item(
        %ItemTemplate{
          entry: 997_980,
          class: 2,
          subclass: 2,
          inventory_type: 15,
          ammo_type: 2,
          dmg_min1: 20.0,
          dmg_max1: 30.0,
          delay: 2000
        },
        guid
      )

    arrows =
      create_item(
        %ItemTemplate{
          entry: 997_981,
          class: 6,
          subclass: 2,
          inventory_type: 24,
          stackable: 200,
          dmg_min1: 5.0,
          dmg_max1: 5.0,
          display_id: 5996
        },
        guid,
        2
      )

    spell = %Spell{id: 75, dmg_class: 3, attributes: MapSet.new([:ignore_line_of_sight])}
    player = Inventory.equip(%Player{inv1: arrows.object.guid, ammo_id: 0}, :ranged, bow)

    character =
      %Character{
        id: guid,
        object: %Object{guid: guid},
        player: player,
        unit: %Unit{
          health: 100,
          max_health: 100,
          level: 50,
          class: 3,
          race: 1,
          power1: 100,
          max_power1: 100,
          power_type: 0
        },
        internal: %Internal{spellbook: %{75 => spell}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }
      |> Equipment.sync_stats()

    SpatialHash.update(:players, guid, WorldRef.open(0), 0.0, 0.0, 0.0)
    SpatialHash.update(:players, guid + 1, WorldRef.open(0), 10.0, 0.0, 0.0)
    Metadata.put(guid + 1, %{alive?: true})

    on_exit(fn ->
      :ets.delete(CharacterStore, guid)
      Metadata.delete(guid)
      SpatialHash.remove(:players, guid)
      Metadata.delete(guid + 1)
      SpatialHash.remove(:players, guid + 1)
    end)

    %{state: %State{guid: guid, ready: true, character: character}, bow: bow, arrows: arrows, spell: spell}
  end
end
