defmodule ThistleTea.Game.Entity.Logic.TriggeredLifetimeTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Aura.Change
  alias ThistleTea.Game.Entity.Logic.Aura.TriggeredLifetime
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  setup [:character]

  describe "transition/2" do
    test "removing a permanent trigger also removes its linked descendants", %{character: character} do
      parent = spell(9000, 3_000, 9001)
      grandchild = spell(9002, -1, 9003)
      child = %{spell(9001, -1, 9002) | linked_auras: [grandchild]}
      child = %{child | effects: [%{hd(child.effects) | aura: :linked_aura}]}

      character =
        character |> apply_spell(parent, 0) |> apply_spell(child, 1_000) |> apply_spell(spell(9003, -1), 2_000)

      assert Enum.map(character.unit.auras, & &1.spell.id) == [9000, 9001, 9002, 9003]
      {expired, _} = Aura.expire_due(character, 3_000)
      assert expired.unit.auras == []
    end

    test "every source removal cleans permanent children through a trigger chain", %{character: character} do
      parent = spell(9000, 3_000, 9001)
      child = spell(9001, -1, 9002)
      grandchild = spell(9002, -1)
      independent = spell(9003, -1)
      character = Enum.reduce([parent, child, grandchild, independent], character, &apply_spell(&2, &1, 0))

      for cause <- Change.causes() -- [:applied, :ticked, :delayed] do
        holders = Enum.reject(character.unit.auras, &(&1.spell.id == parent.id))
        {removed, _} = Aura.transition(character, %Change{holders: holders, cause: cause, now: 1_000})
        assert Enum.map(removed.unit.auras, & &1.spell.id) == [independent.id]
      end

      {expired, _} = Aura.expire_due(character, 3_000)
      assert Enum.map(expired.unit.auras, & &1.spell.id) == [independent.id]
    end

    test "source refresh retains its permanent child but finite buffs expire independently", %{character: character} do
      parent = spell(9000, 3_000, 9001)
      child = %{spell(9001, -1) | stack_amount: 6}
      character = character |> apply_spell(parent, 0) |> apply_spell(child, 1_000) |> apply_spell(child, 1_500)
      refreshed = apply_spell(character, parent, 2_000)
      assert Enum.find(refreshed.unit.auras, &(&1.spell.id == child.id)).stacks == 2
      {expired, _} = Aura.expire_due(refreshed, 3_000)
      assert length(expired.unit.auras) == 2
      assert {_, []} = Aura.expire_due(expired, 4_999)
      {expired, _} = Aura.expire_due(expired, 5_000)
      assert expired.unit.auras == []

      finite = %{child | duration_ms: 10_000}
      character = apply_spell(character, finite, 2_000)
      {expired, _} = Aura.expire_due(character, 3_000)
      assert [%{spell: %{id: 9001}, expires_at: 12_000}] = expired.unit.auras
    end

    test "a one-tick periodic source leaves its permanent result active", %{character: character} do
      parent = spell(9000, 3_000, 9001)
      effect = %{hd(parent.effects) | aura: :periodic_trigger_spell, amplitude_ms: 3_000}
      parent = %{parent | effects: [effect]}
      child = spell(9001, -1)
      character = character |> apply_spell(parent, 0) |> apply_spell(child, 3_000)
      assert TriggeredLifetime.source(character, parent, child) == nil
      {expired, _} = Aura.expire_due(character, 3_000)
      assert [%{spell: %{id: 9001}}] = expired.unit.auras
    end
  end

  describe "apply_spell/4" do
    test "late delivery cannot restore a child after source removal, replacement or expiry", %{character: character} do
      parent = spell(9000, 3_000, 9001)
      child = spell(9001, -1)
      buffed = apply_spell(character, parent, 0)

      context = %CastContext{
        caster_guid: 1,
        caster_level: 60,
        required_aura_source: TriggeredLifetime.source(buffed, parent, child)
      }

      {applied, _} = Aura.apply_spell(buffed, context, child, 1_000)
      assert Enum.any?(applied.unit.auras, &(&1.spell.id == child.id))
      assert {^character, []} = Aura.apply_spell(character, context, child, 1_000)
      assert {^buffed, []} = Aura.apply_spell(buffed, context, child, 3_000)
      refreshed = apply_spell(buffed, parent, 1_000)
      assert {^refreshed, []} = Aura.apply_spell(refreshed, context, child, 2_000)

      missing = %{context | required_aura_source: TriggeredLifetime.source(character, parent, child)}
      assert missing.required_aura_source == :missing
      assert {^character, []} = Aura.apply_spell(character, missing, child, 1_000)
    end
  end

  defp character(_context) do
    %{
      character: %Character{
        object: %Object{guid: 1},
        player: %Player{},
        internal: %Internal{},
        unit: %Unit{level: 60, health: 100, max_health: 100, auras: []}
      }
    }
  end

  defp apply_spell(character, spell, now), do: elem(Aura.apply_spell(character, 1, 60, spell, now), 0)

  defp spell(id, duration, trigger \\ nil) do
    %Spell{
      id: id,
      duration_ms: duration,
      effects: [
        %Effect{index: 0, type: :apply_aura, aura: :proc_trigger_spell, trigger_spell_id: trigger}
      ]
    }
  end
end
