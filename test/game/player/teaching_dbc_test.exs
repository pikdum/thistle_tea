defmodule ThistleTea.Game.Player.TeachingDbcTest do
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
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.SpellTeaching
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network.BinaryUtils
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.ItemCosts
  alias ThistleTea.Game.Player.Spells
  alias ThistleTea.Game.Player.Teaching
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Skill, as: SkillLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  @moduletag :dbc_db

  setup_all do
    SkillLoader.load_all()
  end

  setup [:character]

  describe "recipe book casting" do
    test "teaches on completion, consumes once, and rejects a duplicate", %{state: state} do
      {state, item} = book(state, 6325, 7756, 1)
      started = use_book(state)
      assert %Cast{cast_item_guid: guid} = started.character.internal.casting
      assert guid == item.object.guid
      assert ItemStore.get(guid) == item
      refute 7751 in started.character.internal.spells

      completed = finish(started)
      assert ItemStore.get(guid) == nil
      assert completed.character.player.inv1 == 0
      assert 7751 in completed.character.internal.spells
      assert CharacterStore.get(state.guid).internal.spells == completed.character.internal.spells
      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgLearnedSpell{spell_id: 7751}}}
      refute_received {:consume_cast_item, _}

      {duplicate, spare} = book(completed, 6325, 7756, 1)
      rejected = use_book(duplicate)
      assert rejected.character.internal.casting == nil
      assert ItemStore.get(spare.object.guid) == spare
      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgCastResult{spell: 7756, reason: 0x62}}}
    end

    test "expert books grant the new rank while preserving earned skill", %{state: state} do
      {state, item} = book(state, 16_072, 19_886, 125)
      completed = state |> use_book() |> finish()
      assert ItemStore.get(item.object.guid) == nil
      assert %{value: 125, max: 225, step: 3} = completed.character.player.skills[185]
      assert completed.character.player.skills[185].slot == state.character.player.skills[185].slot
      assert 3413 in completed.character.internal.spells
      refute 3102 in completed.character.internal.spells
      assert CharacterStore.get(state.guid).player.skills == completed.character.player.skills
    end

    test "cancellation preserves the book and teaches nothing", %{state: state} do
      {state, item} = book(state, 6325, 7756, 1)
      started = use_book(state)
      cancelled = Casting.cancel(started.character)
      completed = Casting.complete(cancelled, started.character.internal.casting.ends_at + 1)
      EventSink.emit_pending(completed, Context.new(self()))
      refute_received {:teach_spell, _}
      assert ItemStore.get(item.object.guid) == item
      refute 7751 in completed.internal.spells
    end

    test "missing, banked, and newly ineligible books cannot teach at completion", %{state: state} do
      {state, item} = book(state, 16_072, 19_886, 125)
      started = use_book(state)
      skills = Map.update!(started.character.player.skills, 185, &%{&1 | value: 124})

      for player <- [
            %{started.character.player | inv1: nil},
            %{started.character.player | inv1: nil, bank1: item.object.guid},
            %{started.character.player | skills: skills}
          ] do
        stale = %{started | character: %{started.character | player: player}}
        completed = finish(stale)
        refute 3413 in completed.character.internal.spells
        assert completed.character.player.skills[185].max == 150
        assert ItemStore.get(item.object.guid) == item
      end
    end

    test "insufficient skill prevents the item cast from starting", %{state: state} do
      {state, item} = book(state, 16_072, 19_886, 125)
      state = put_in(state.character.player.skills[185].value, 124)
      rejected = use_book(state)
      assert rejected.character.internal.casting == nil
      assert ItemStore.get(item.object.guid) == item
      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgInventoryChangeFailure{}}}
    end

    test "invalid taught spells and missing reagents leave books and skills untouched", %{state: state} do
      {state, item} = book(state, 16_072, 19_886, 125)
      original = SpellLoader.load(19_886)

      for spell <- [
            %{original | effects: [%Effect{type: :learn_spell, trigger_spell_id: 999_999}]},
            %{original | reagents: [{999_999, 1}]}
          ] do
        effect = %Effects.TeachSpell{spell: spell, skill_steps: [{185, 3}], cast_item_guid: item.object.guid}
        assert Teaching.complete(state, effect) == state
        assert ItemStore.get(item.object.guid) == item
        refute 3413 in CharacterStore.get(state.guid).internal.spells
      end
    end
  end

  describe "complete/2" do
    test "skill-only effects set exact caps and survive later unrelated learning", %{state: state} do
      spell = %Spell{id: 99_999, effects: [%Effect{type: :skill_step, misc_value: 185, base_points: 0, base_dice: 1}]}
      effect = %Effects.TeachSpell{spell: spell, skill_steps: [{185, 1}]}
      completed = Teaching.complete(state, effect)
      assert %{value: 125, max: 75, step: 1} = completed.character.player.skills[185]
      assert {:ok, learned, _events} = Spells.learn(completed.character, [5697])
      assert %{value: 125, max: 75, step: 1} = learned.player.skills[185]
    end

    test "trade settlement commits an already queued teaching transaction", %{state: state} do
      {state, item} = book(state, 6325, 7756, 1)
      spell = SpellLoader.load(7756)
      effect = %Effects.TeachSpell{spell: spell, skill_steps: [], cast_item_guid: item.object.guid}
      send(self(), {:teach_spell, effect})
      completed = ItemCosts.settle(state)
      assert ItemStore.get(item.object.guid) == nil
      assert 7751 in completed.character.internal.spells
    end
  end

  defp use_book(state) do
    message = %Message.CmsgUseItem{bag: Inventory.bag_0(), slot: 23, spell_count: 1, targets: <<0::little-size(16)>>}
    Message.CmsgUseItem.handle(message, state)
  end

  defp finish(%State{character: %{internal: %{casting: %Cast{} = cast}}} = state) do
    character = state.character |> Casting.complete(cast.ends_at + 1) |> EventSink.emit_pending(Context.new(self()))
    assert_received {:teach_spell, %Effects.TeachSpell{} = effect}
    assert effect.skill_steps == SpellTeaching.skill_steps(effect.spell)
    ItemCosts.apply(%{state | character: character}, {:teach_spell, effect})
  end

  defp book(state, entry, spell_id, required_rank) do
    template = %ItemTemplate{
      entry: entry,
      name: "Teaching book",
      stackable: 1,
      required_skill: 185,
      required_skill_rank: required_rank,
      spellid_1: spell_id,
      spelltrigger_1: 0,
      spellcharges_1: -1
    }

    item = ItemStore.create(template, owner: state.guid)
    on_exit(fn -> ItemStore.delete(item.object.guid) end)
    {put_in(state.character.player.inv1, item.object.guid), item}
  end

  defp character(_context) do
    character =
      CharacterStore.create(%Character{
        id: 0,
        object: %Object{guid: 0},
        player: %Player{skills: %{}},
        unit: %Unit{race: 1, class: 8, level: 50, health: 100, max_health: 100, power1: 100, max_power1: 100},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{world: WorldRef.open(0), spells: [], spellbook: %{}}
      })

    {:ok, character, _events} = Spells.learn(character, [3102])
    character = put_in(character.player.skills[185].value, 125)
    CharacterStore.put(character)
    guid = character.object.guid
    {:ok, _} = Entity.register(guid)

    on_exit(fn ->
      :ets.delete(CharacterStore, guid)
      Metadata.delete(guid)
      SpatialHash.remove(:players, guid)
    end)

    %{state: %State{guid: guid, ready: true, packed_guid: BinaryUtils.pack_guid(guid), character: character}}
  end
end
