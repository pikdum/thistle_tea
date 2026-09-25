defmodule ThistleTea.Game.Player.FormPassivesDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.PassiveSpells
  alias ThistleTea.Game.Entity.Logic.SpellEnvironment
  alias ThistleTea.Game.Entity.Logic.SpellRemoval
  alias ThistleTea.Game.Player.Spells
  alias ThistleTea.Game.World.Loader.PassiveSpell
  alias ThistleTea.Game.World.Loader.Skill
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.Talent

  @moduletag :dbc_db

  setup_all do
    Skill.load_all()
    Talent.load_all()
    previous = for id <- [17_002, 24_866], do: {id, :ets.lookup(PassiveSpell, id)}
    :ets.insert(PassiveSpell, [{17_002, [24_867]}, {24_866, [24_864]}])

    on_exit(fn ->
      Enum.each(previous, fn {id, rows} ->
        :ets.delete(PassiveSpell, id)
        :ets.insert(PassiveSpell, rows)
      end)
    end)

    :ok
  end

  setup [:character]

  describe "prepare/2" do
    test "learning and upgrading in form update stats without duplicate ranks", %{character: character} do
      {cat, _events} = cast(character, 768, 1000)
      assert {:ok, learned, _events} = Spells.prepare(cat, [16_942])
      assert Aura.flat_amount(learned, :mod_crit_percent) == 2
      assert {:ok, upgraded, _events} = Spells.prepare(learned, [16_943])
      refute Aura.has_spell?(upgraded, 16_942)
      assert Aura.flat_amount(upgraded, :mod_crit_percent) == 4
      assert upgraded.player.crit_percentage > learned.player.crit_percentage
    end

    test "hidden dodge survives indoors independently of speed and follows rank and unlearning", %{character: character} do
      {cat, _events} = cast(character, 768, 1000)
      assert {:ok, learned, _events} = Spells.prepare(cat, [17_002])
      assert Aura.has_spell?(learned, 24_867)
      assert Aura.flat_amount(learned, :mod_dodge) == 2
      assert Enum.find(learned.unit.auras, &(&1.spell.id == 24_867)).slot == nil
      assert_in_delta learned.movement_block.run_speed, 8.05, 0.00001
      refute 24_867 in learned.internal.spells

      assert {:ok, upgraded, _events} = Spells.prepare(learned, [24_866])
      refute Aura.has_spell?(upgraded, 17_002)
      refute Aura.has_spell?(upgraded, 24_867)
      assert Aura.flat_amount(upgraded, :mod_dodge) == 4
      assert Enum.find(upgraded.unit.auras, &(&1.spell.id == 24_864)).slot == nil
      assert_in_delta upgraded.movement_block.run_speed, 9.1, 0.00001

      inside = %{upgraded | internal: %{upgraded.internal | outdoors?: false}} |> SpellEnvironment.reconcile(2000)
      assert inside.movement_block.run_speed == 7.0
      assert Aura.has_spell?(inside, 24_864)
      assert inside.player.dodge_percentage == upgraded.player.dodge_percentage

      removed = SpellRemoval.remove(inside, [24_866], 3000)
      refute Aura.has_spell?(removed, 24_864)
      assert removed.player.dodge_percentage < inside.player.dodge_percentage
      {bear, _events} = cast(removed, 5487, 4000)
      {cat, _events} = cast(bear, 768, 5000)
      refute Aura.has_spell?(cat, 24_864)
    end

    test "rebuilding the login spellbook restores hidden passives in the retained form", %{character: character} do
      assert {:ok, learned, _events} = Spells.prepare(character, [24_866])
      refute Aura.has_spell?(learned, 24_864)
      {cat, _events} = cast(learned, 768, 1000)
      {cat, _events} = Aura.remove_spells(cat, [24_864, 24_866], 2000)
      cat = %{cat | internal: %{cat.internal | spellbook: SpellLoader.build_spellbook(cat.internal.spells)}}
      {restored, _events} = PassiveSpells.restore(cat, 3000)
      assert Aura.has_spell?(restored, 24_864)
      assert Aura.has_spell?(restored, 24_866)
    end
  end

  defp character(_context) do
    character = %Character{
      object: %Object{guid: 1},
      unit: %Unit{health: 100, max_health: 100, level: 60, race: 4, class: 11, auras: []},
      player: %Player{},
      internal: %Internal{outdoors?: true, spells: [], spellbook: %{}},
      movement_block: struct!(%MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}, MovementBlock.player_speeds())
    }

    %{character: character}
  end

  defp cast(character, id, now), do: Aura.apply_spell(character, 1, 60, SpellLoader.load(id), now)
end
