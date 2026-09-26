defmodule ThistleTea.Game.Entity.Logic.SpellGroupStackingTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastValidation
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.StackRules
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.WorldRef

  setup [:character]

  describe "apply_spell/5" do
    test "exclusive buffs replace across casters and remove all predecessor bonuses", %{character: c} do
      first = buff(1, 10, 1)
      second = buff(2, 5, 1)
      {c, _} = Aura.apply_spell(c, 2, 60, first, 1000)
      {c, _} = Aura.apply_spell(c, 3, 60, second, 2000)
      assert ids(c) == [2]
      assert c.unit.strength == 15
      {c, _} = Aura.expire_due(c, 32_000)
      assert ids(c) == []
      assert c.unit.strength == 10
    end

    test "ordered upgrades replace and reject downgrades without refreshing", %{character: c} do
      lower = buff(1, 10, 3)
      higher = buff(2, 20, 3)
      {c, _} = Aura.apply_spell(c, 2, 60, lower, 1000)
      {c, _} = Aura.apply_spell(c, 3, 60, higher, 2000)
      assert ids(c) == [2]
      assert c.unit.strength == 30
      assert {^c, []} = Aura.apply_spell(c, 4, 60, lower, 31_999)
      {c, _} = Aura.expire_due(c, 32_000)
      assert ids(c) == []
      assert c.unit.strength == 10
    end

    test "rejection is atomic when another group would remove a different holder", %{character: c} do
      lower = buff(1, 10, 3)
      higher = buff(2, 20, 3)
      unrelated = %{buff(3, 5, 1) | stack_rules: %StackRules{groups: %{2 => 1}}}
      lower = %{lower | stack_rules: %{lower.stack_rules | groups: Map.put(lower.stack_rules.groups, 2, 1)}}
      {c, _} = Aura.apply_spell(c, 2, 60, higher, 1000)
      {c, _} = Aura.apply_spell(c, 3, 60, unrelated, 1000)
      assert {^c, []} = Aura.apply_spell(c, 4, 60, lower, 2000)
      assert ids(c) == [2, 3]
    end

    test "death clears the replacement without restoring its predecessor", %{character: c} do
      {c, _} = Aura.apply_spell(c, 2, 60, buff(1, 10, 3), 1000)
      {c, _} = Aura.apply_spell(c, 3, 60, buff(2, 20, 3), 2000)
      c = Core.take_damage(c, 1000, 3000)
      assert ids(c) == []
      assert c.unit.strength == 10
    end
  end

  describe "validate/6" do
    test "positive single-target upgrades reject weaker casts on self and others", %{character: c} do
      lower = buff(1, 10, 3)
      {target, _} = Aura.apply_spell(c, 2, 60, buff(2, 20, 3), 1000)
      assert CastValidation.validate(target, lower, Target.unit(1), nil, 2000) == {:error, :aura_bounced}
      info = %{aura_sources: Aura.source_spells(target)}
      assert CastValidation.validate(c, lower, Target.unit(2), info, 2000) == {:error, :aura_bounced}
    end

    test "area buffs and harmful debuffs defer conflicts to each recipient", %{character: c} do
      {c, _} = Aura.apply_spell(c, 2, 60, buff(2, 20, 3), 1000)
      lower = buff(1, 10, 3)
      harmful = %{lower | attributes: MapSet.new([:negative])}
      area = %{lower | effects: Enum.map(lower.effects, &%{&1 | area_target?: true})}
      assert CastValidation.validate(c, harmful, Target.unit(1), nil, 2000) == :ok
      assert CastValidation.validate(c, area, Target.unit(1), nil, 2000) == :ok
    end
  end

  defp buff(id, amount, rule) do
    rules = %StackRules{
      groups: %{1 => rule},
      priorities: %{1 => id},
      stronger: if(rule == 3 and id == 1, do: MapSet.new([2]), else: MapSet.new()),
      weaker: if(rule == 3 and id == 2, do: MapSet.new([1]), else: MapSet.new())
    }

    %Spell{
      id: id,
      stack_rules: rules,
      duration_ms: 30_000,
      effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_stat, base_points: amount, misc_value: 0}]
    }
  end

  defp ids(c), do: c.unit.auras |> Enum.map(& &1.spell.id) |> Enum.sort()

  defp character(_context) do
    %{
      character: %Character{
        object: %Object{guid: 1},
        unit: %Unit{health: 100, max_health: 1000, base_strength: 10, strength: 10, level: 60, auras: []},
        player: %Player{},
        internal: %Internal{world: WorldRef.open(0)},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }
    }
  end
end
