defmodule ThistleTea.Game.Player.SpellAreasTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.QuestLog.Entry
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Player.SpellAreas
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Area
  alias ThistleTea.Game.Spell.Area.Context
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.WorldRef

  describe "reconcile/2" do
    setup [:character_and_rules]

    test "applies once, preserves alternatives, removes on exit and restores on reentry", %{
      state: state,
      options: options
    } do
      active = SpellAreas.reconcile(state, options)
      assert Aura.has_spell?(active.character, 31_906)
      assert SpellAreas.reconcile(active, options) == active
      alternative = SpellAreas.reconcile(active, Keyword.put(options, :context, %Context{zone_id: 2017}))
      assert alternative.character.unit.auras == active.character.unit.auras
      outside = SpellAreas.reconcile(alternative, Keyword.put(options, :context, %Context{zone_id: 148}))
      refute Aura.has_spell?(outside.character, 31_906)
      assert Aura.has_spell?(outside.character, 30_238)
      assert Aura.has_spell?(SpellAreas.reconcile(outside, options).character, 31_906)
    end

    test "removes dependent auras when their prerequisite disappears", %{state: state, options: options} do
      active = SpellAreas.reconcile(state, options)
      {character, _} = Aura.remove_spells(active.character, [30_238], 2000)
      removed = SpellAreas.reconcile(%{active | character: character}, options)
      refute Aura.has_spell?(removed.character, 31_906)
    end

    test "reevaluates death, resurrection and a new login owner", %{state: state, options: options} do
      character = %{state.character | unit: %{state.character.unit | health: 0}}
      dead = SpellAreas.reconcile(%{state | character: character}, options)
      refute Aura.has_spell?(dead.character, 31_906)
      character = %{dead.character | unit: %{dead.character.unit | health: 100}}
      alive = SpellAreas.reconcile(%{dead | character: character}, options)
      assert Aura.has_spell?(alive.character, 31_906)

      restored =
        SpellAreas.reconcile(%State{character: alive.character}, Keyword.put(options, :context, %Context{zone_id: 148}))

      refute Aura.has_spell?(restored.character, 31_906)
    end

    test "quest acceptance grants an aura and rewarding the quest removes it", %{state: state} do
      rule = %Area{spell_id: 100, quest_start: 10, quest_start_active?: true, quest_end: 10, autocast?: true}
      spell = aura_spell(100, [rule])
      options = [rules: [rule], context: %Context{}, spell_lookup: fn 100 -> spell end, now: 1000]
      absent = SpellAreas.reconcile(state, options)
      refute Aura.has_spell?(absent.character, 100)
      character = %{absent.character | player: %{absent.character.player | quest_log: %{0 => %Entry{quest_id: 10}}}}
      accepted = SpellAreas.reconcile(%{absent | character: character}, options)
      assert Aura.has_spell?(accepted.character, 100)
      character = %{accepted.character | player: %{accepted.character.player | rewarded_quests: MapSet.new([10])}}
      rewarded = SpellAreas.reconcile(%{accepted | character: character}, options)
      refute Aura.has_spell?(rewarded.character, 100)
    end
  end

  defp character_and_rules(_context) do
    rules = for area <- [139, 2017], do: %Area{spell_id: 31_906, area_id: area, aura_spell: 30_238, autocast?: true}
    child = aura_spell(31_906, rules)

    character = %Character{
      object: %Object{guid: System.unique_integer([:positive])},
      unit: %Unit{level: 60, race: 1, gender: 1, health: 100, max_health: 100, auras: []},
      player: %Player{},
      internal: %Internal{world: %WorldRef{map_id: 0}},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    {character, _} = Aura.apply_spell(character, character.object.guid, 60, aura_spell(30_238, []), 1000)

    %{
      state: %State{character: character},
      options: [rules: rules, context: %Context{zone_id: 139}, spell_lookup: fn 31_906 -> child end, now: 1000]
    }
  end

  defp aura_spell(id, rules) do
    %Spell{
      id: id,
      school: :holy,
      duration_ms: -1,
      area_rules: rules,
      effects: [%Effect{index: 0, type: :apply_aura, aura: :dummy, implicit_target_a: :caster, base_points: 0}]
    }
  end
end
