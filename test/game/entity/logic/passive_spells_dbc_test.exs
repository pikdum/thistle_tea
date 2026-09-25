defmodule ThistleTea.Game.Entity.Logic.PassiveSpellsDbcTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.PassiveSpells
  alias ThistleTea.Game.Spell.Passive
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "restore/3" do
    test "Defiance follows Defensive Stance and restores from the learned spellbook" do
      character = character([12_792], 1)
      {battle, _events} = cast(character, 2457, 1000)
      refute Aura.has_spell?(battle, 12_792)
      {defensive, _events} = cast(battle, 71, 2000)
      assert Aura.flat_modifier(defensive, :mod_threat, 1) == 45
      {berserker, _events} = cast(defensive, 2458, 3000)
      refute Aura.has_spell?(berserker, 12_792)
    end

    test "feral critical strike, stealth, proc and falling passives follow their DBC forms" do
      ids = [16_944, 16_951, 16_954, 16_961, 20_719]
      character = character(ids, 11)
      {cat, _events} = cast(character, 768, 1000)
      assert Enum.all?([16_944, 16_951, 16_954, 20_719], &Aura.has_spell?(cat, &1))
      refute Aura.has_spell?(cat, 16_961)
      assert Aura.flat_amount(cat, :mod_crit_percent) == 6

      {bear, _events} = cast(cat, 5487, 2000)
      assert Enum.all?([16_944, 16_951, 16_961], &Aura.has_spell?(bear, &1))
      refute Aura.has_spell?(bear, 16_954)
      refute Aura.has_spell?(bear, 20_719)
      {normal, _events} = Aura.cancel_spell(bear, 5487, 3000)
      refute Enum.any?(ids, &Aura.has_spell?(normal, &1))
      assert {^normal, []} = PassiveSpells.restore(normal, 4000)
    end

    test "Enrage ends with Bear Form while stance-independent warrior buffs survive" do
      {bear, _events} = cast(character([], 11), 5487, 1000)
      {enraged, _events} = cast(bear, 5229, 2000)
      assert Aura.has_spell?(enraged, 5229)
      {normal, _events} = Aura.cancel_spell(enraged, 5487, 3000)
      refute Aura.has_spell?(normal, 5229)
      refute Passive.removed_on_shape_lost?(SpellLoader.load(18_499))
    end
  end

  defp character(ids, class) do
    %Character{
      object: %Object{guid: 1},
      unit: %Unit{health: 100, max_health: 100, level: 60, class: class, auras: []},
      player: %Player{},
      internal: %Internal{spells: ids, spellbook: SpellLoader.build_spellbook(ids)},
      movement_block: struct!(%MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}, MovementBlock.player_speeds())
    }
  end

  defp cast(character, id, now), do: Aura.apply_spell(character, 1, 60, SpellLoader.load(id), now)
end
