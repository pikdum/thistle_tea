defmodule ThistleTea.Game.World.Loader.ItemSetDbcTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.ItemSet
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Aura.Application
  alias ThistleTea.Game.Entity.Logic.EquipmentAuras
  alias ThistleTea.Game.Entity.Logic.EquipmentSets
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network.Message.CmsgMessagechat
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.ItemSet, as: ItemSetLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.WorldRef

  @moduletag :dbc_db

  setup [:equipment]

  describe "load_all/1" do
    test "loads all thresholds and profession requirements", %{table: table} do
      assert %ItemSet{name: "The Gladiator", bonuses: [{2, 9761}, {3, 7514}, {4, 9140}, {5, 7597}]} =
               ItemSetLoader.get(1, table)

      assert %ItemSet{required_skill: 197, required_skill_rank: 300, bonuses: [{3, 18_382}]} =
               ItemSetLoader.get(421, table)

      assert ItemSetLoader.get(0, table) == nil
    end
  end

  describe "sync_equipment_stats/1" do
    test "applies real bonuses through equipment and reconnect resync", %{character: character, set_id: set_id} do
      set = %ItemSet{id: set_id, bonuses: [{2, 9761}, {3, 7514}]}
      :ets.insert(ItemSetLoader, {set_id, set})
      equipped = Character.sync_equipment_stats(character)
      assert equipped.unit.normal_resistance == 20
      assert equipped.player.skill_bonuses == %{95 => {2, 0}}
      assert length(equipped.unit.auras) == 2
      assert Character.sync_equipment_stats(equipped).unit.auras == equipped.unit.auras

      character = %{equipped | player: %{equipped.player | head: nil}}
      removed = Character.sync_equipment_stats(character)
      assert removed.unit.normal_resistance == 20
      assert removed.player.skill_bonuses == %{}
      removed = Character.sync_equipment_stats(%{removed | player: %{removed.player | chest: nil}})
      assert removed.unit.normal_resistance == 0
      assert removed.unit.auras == []
    end

    test "rechecks profession gains and loss at the owner publication boundary", %{character: character, set_id: set_id} do
      set = %ItemSet{id: set_id, required_skill: 197, required_skill_rank: 300, bonuses: [{3, 18_382}]}
      :ets.insert(ItemSetLoader, {set_id, set})
      character = Character.sync_equipment_stats(character)
      state = PlayerServer.maybe_broadcast_update(%State{guid: character.object.guid, character: character})
      assert state.character.unit.auras == []
      fireball = SpellLoader.load(133)
      baseline = CastContext.from_caster(state.character, fireball, 2).spell_crit_chance
      state = put_in(state.character.player.skills, %{197 => %{value: 299, max: 300, range: :tier}})
      message = %CmsgMessagechat{chat_type: 0, language: 0, message: ".debug professions"}
      assert {:reply, :ok, state} = PlayerServer.handle_call({:client_message, message}, nil, state)
      assert Aura.flat_modifier(state.character, :mod_spell_crit_chance_school, 4) == 2
      assert CastContext.from_caster(state.character, fireball, 2).spell_crit_chance == baseline + 2
      state = put_in(state.character.player.skills, %{})
      state = PlayerServer.maybe_broadcast_update(state)
      assert Aura.flat_modifier(state.character, :mod_spell_crit_chance_school, 4) == 0
    end

    test "rechecks the real feral speed bonus on form entry and exit", %{character: character, set_id: set_id} do
      :ets.insert(ItemSetLoader, {set_id, %ItemSet{id: set_id, bonuses: [{3, 23_218}]}})
      character = Character.sync_equipment_stats(character)
      state = PlayerServer.maybe_broadcast_update(%State{guid: character.object.guid, character: character})
      assert state.character.movement_block.run_speed == 7.0
      {shifted, _} = Application.apply_spell(character, character.object.guid, 60, SpellLoader.load(768), 100)
      state = PlayerServer.maybe_broadcast_update(%{state | character: shifted})
      assert_in_delta state.character.movement_block.run_speed, 8.05, 0.001
      {restored, _} = Aura.cancel_spell(state.character, 768, 200)
      state = PlayerServer.maybe_broadcast_update(%{state | character: restored})
      assert state.character.movement_block.run_speed == 7.0
      refute Aura.has_spell?(state.character, 23_218)
    end
  end

  describe "sync/5" do
    test "real Spider's Kiss grants its proc only while both pieces are equipped", %{character: character, table: table} do
      templates = [%ItemTemplate{item_set: 65}, %ItemTemplate{item_set: 65}]
      sources = EquipmentSets.sources(character, templates, &ItemSetLoader.get(&1, table))
      equipped = EquipmentAuras.sync(character, [], &SpellLoader.load/1, 0, sources)

      assert [%{spell: %{id: 17_332}, auras: [%{type: :proc_trigger_spell, trigger_spell_id: 17_333}]}] =
               equipped.unit.auras

      assert EquipmentAuras.sync(equipped, [], &SpellLoader.load/1, 100, []).unit.auras == []
    end
  end

  defp equipment(_context) do
    table = :ets.new(:item_sets, [:public])
    :ok = ItemSetLoader.load_all(table)
    set_id = System.unique_integer([:positive]) + 1_000_000
    items = for _ <- 1..3, do: ItemStore.create(%ItemTemplate{entry: set_id, item_set: set_id})

    player =
      Enum.zip([:head, :chest, :feet], items)
      |> Enum.reduce(%Player{}, fn {slot, item}, player -> Inventory.equip(player, slot, item) end)

    on_exit(fn ->
      for item <- items, do: ItemStore.delete(item.object.guid)
      :ets.delete(ItemSetLoader, set_id)
      :ets.delete(CharacterStore, set_id)
    end)

    character = %Character{
      id: set_id,
      object: %Object{guid: set_id, scale_x: 1.0},
      player: player,
      unit: %Unit{
        health: 100,
        max_health: 100,
        base_health: 100,
        base_normal_resistance: 0,
        intellect: 20,
        level: 60,
        class: 11,
        race: 4,
        auras: []
      },
      internal: %Internal{world: WorldRef.open(0)},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, base_run_speed: 7.0, run_speed: 7.0}
    }

    %{character: character, set_id: set_id, table: table}
  end
end
