defmodule ThistleTea.Game.Entity.Logic.Aura.LinkedTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Aura.Change
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  setup [:character_and_spells]

  describe "apply_spell/5" do
    test "applies a hidden child owned by the parent", %{character: character, parent: parent} do
      {active, _events} = Aura.apply_spell(character, 2, 50, parent, 1_000)
      assert [root, child] = active.unit.auras
      assert root.spell.id == 100
      assert root.slot == 0
      assert child.spell.id == 101
      assert child.caster_guid == character.object.guid
      assert child.linked_from == {Holder.key(root), 1_000}
      assert child.slot == nil
      assert Spell.attribute?(child.spell, :passive)

      {damaged, 80, 0} = Core.take_damage_with_mitigation(active, 100, 1_100, school: :physical)
      assert damaged.unit.health == 920
      {_damaged, 100, 0} = Core.take_damage_with_mitigation(active, 100, 1_100, school: :fire)
    end

    test "refresh replaces the child without multiplying its effect", %{character: character, parent: parent} do
      {active, _} = Aura.apply_spell(character, 1, 60, parent, 1_000)
      {active, _} = Aura.apply_spell(active, 1, 60, parent, 5_000)
      assert [root, child] = active.unit.auras
      assert child.linked_from == {Holder.key(root), 5_000}
      assert child.expires_at == 25_000
      assert Aura.percent_multiplier(active, :mod_damage_percent_taken, 1) == 0.8
    end

    test "removing the parent preserves an independent copy", %{character: character, parent: parent, child: child} do
      {active, _} = Aura.apply_spell(character, 1, 60, parent, 1_000)
      {active, _} = Aura.apply_spell(active, 1, 60, child, 2_000)
      assert length(active.unit.auras) == 3
      {removed, _} = Aura.cancel_spell(active, parent.id, 3_000)
      assert [%Holder{spell: %Spell{id: 101}, linked_from: nil}] = removed.unit.auras
    end

    test "blocked applications never grant children", %{character: character, parent: parent} do
      stronger = %{parent | id: 102, first_in_chain: 100, rank: 2, linked_auras: []}
      weaker = %{parent | first_in_chain: 100, rank: 1}
      {active, _} = Aura.apply_spell(character, 1, 60, stronger, 1_000)
      {rejected, []} = Aura.apply_spell(active, 1, 60, weaker, 2_000)
      assert rejected == active
      assert Enum.map(rejected.unit.auras, & &1.spell.id) == [102]
    end
  end

  describe "transition/2" do
    test "all parent-removal causes remove its retained child", %{character: character, parent: parent} do
      {active, _} = Aura.apply_spell(character, 1, 60, parent, 1_000)
      [_root, child] = active.unit.auras

      for cause <- Change.causes() do
        {removed, _} = Aura.transition(active, %Change{holders: [child], cause: cause, now: 2_000})
        assert removed.unit.auras == []
        assert Aura.percent_multiplier(removed, :mod_damage_percent_taken, 1) == 1.0
      end
    end

    test "retains consumed child state across unrelated transitions", %{character: character, parent: parent} do
      {active, _} = Aura.apply_spell(character, 1, 60, parent, 1_000)
      [root, child] = active.unit.auras
      child = %{child | charges: 1, auras: Enum.map(child.auras, &%{&1 | amount: -10})}
      {changed, _} = Aura.transition(active, %Change{holders: [root, child], cause: :consumed, now: 2_000})
      assert List.last(changed.unit.auras) == child
      {unchanged, []} = Aura.transition(changed, %Change{holders: changed.unit.auras, cause: :ticked, now: 3_000})
      assert unchanged == changed
    end

    test "does not recreate a removed child until the parent refreshes", %{character: character, parent: parent} do
      {active, _} = Aura.apply_spell(character, 1, 60, parent, 1_000)
      {removed, _} = Aura.remove_spells(active, [101], 2_000)
      {removed, _} = Aura.tick(removed, 3_000)
      assert Enum.map(removed.unit.auras, & &1.spell.id) == [100]
      {refreshed, _} = Aura.apply_spell(removed, 1, 60, parent, 4_000)
      assert Enum.map(refreshed.unit.auras, & &1.spell.id) == [100, 101]
    end

    test "nested children leave with their root", %{character: character, parent: parent, child: child} do
      nested = %{child | id: 102}
      child = %{child | effects: child.effects ++ [link_effect(102)], linked_auras: [nested]}
      parent = %{parent | linked_auras: [child]}
      {active, _} = Aura.apply_spell(character, 1, 60, parent, 1_000)
      assert Enum.map(active.unit.auras, & &1.spell.id) == [100, 101, 102]
      {removed, _} = Aura.cancel_spell(active, 100, 2_000)
      assert removed.unit.auras == []
    end
  end

  describe "expire_due/2" do
    test "parent expiry removes longer-lived passive children", %{character: character, parent: parent} do
      {active, _} = Aura.apply_spell(character, 1, 60, parent, 1_000)
      {expired, _} = Aura.expire_due(active, 13_000)
      assert expired.unit.auras == []
    end

    test "child expiry does not refresh it", %{character: character, parent: parent, child: child} do
      parent = %{parent | linked_auras: [%{child | duration_ms: 1_000}]}
      {active, _} = Aura.apply_spell(character, 1, 60, parent, 1_000)
      {expired, _} = Aura.expire_due(active, 2_000)
      {expired, _} = Aura.tick(expired, 3_000)
      assert Enum.map(expired.unit.auras, & &1.spell.id) == [100]
    end
  end

  describe "take_damage/4" do
    test "death removes the passive child with its parent", %{character: character, parent: parent} do
      {active, _} = Aura.apply_spell(character, 1, 60, parent, 1_000)
      dead = Core.take_damage(active, 2_000, 2_000, school: :fire)
      assert dead.unit.health == 0
      assert dead.unit.auras == []
    end
  end

  defp character_and_spells(_context) do
    character = %Character{
      object: %Object{guid: 1},
      unit: %Unit{level: 60, health: 1_000, max_health: 1_000, base_attack_time: 2_000, auras: []},
      player: %Player{},
      internal: %Internal{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, movement_flags: 0}
    }

    child = %Spell{
      id: 101,
      duration_ms: 20_000,
      effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_damage_percent_taken, base_points: -20, misc_value: 1}]
    }

    parent = %Spell{id: 100, duration_ms: 12_000, effects: [link_effect(101)], linked_auras: [child]}
    %{character: character, parent: parent, child: child}
  end

  defp link_effect(id), do: %Effect{index: 1, type: :apply_aura, aura: :linked_aura, trigger_spell_id: id}
end
