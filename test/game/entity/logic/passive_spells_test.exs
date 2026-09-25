defmodule ThistleTea.Game.Entity.Logic.PassiveSpellsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.PassiveSpells
  alias ThistleTea.Game.Entity.Logic.SpellRemoval
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  setup [:character]

  describe "restore/3" do
    test "form entry and exit atomically activate and remove learned talents", %{character: character, talent: talent} do
      assert {^character, []} = PassiveSpells.restore(character, 1000)
      {cat, _events} = apply_spell(character, form(1), 1000)
      assert Aura.has_spell?(cat, talent.id)
      assert Aura.flat_amount(cat, :mod_crit_percent) == 6

      {bear, _events} = apply_spell(cat, form(5), 2000)
      assert Aura.flat_amount(bear, :mod_crit_percent) == 6
      assert length(Enum.filter(bear.unit.auras, &(&1.spell.id == talent.id))) == 1

      {normal, _events} = Aura.cancel_spell(bear, form(5).id, 3000)
      assert normal.unit.shapeshift_form == 0
      refute Aura.has_spell?(normal, talent.id)
      assert Aura.flat_amount(normal, :mod_crit_percent) == 0
    end

    test "restoring preserves holder charge and proc state", %{character: character, talent: talent} do
      {cat, _events} = apply_spell(character, form(1), 1000)

      holders =
        Enum.map(cat.unit.auras, fn holder ->
          if holder.spell.id == talent.id, do: %{holder | charges: 2, next_proc_at: 5000}, else: holder
        end)

      cat = %{cat | unit: %{cat.unit | auras: holders}}
      assert {^cat, []} = PassiveSpells.restore(cat, 2000)
    end

    test "unlearning prevents later form restoration", %{character: character, talent: talent} do
      {cat, _events} = apply_spell(character, form(1), 1000)
      unlearned = SpellRemoval.remove(cat, [talent.id], 2000)
      refute Aura.has_spell?(unlearned, talent.id)
      {bear, _events} = apply_spell(unlearned, form(5), 3000)
      refute Aura.has_spell?(bear, talent.id)
    end

    test "death and release cannot restore talents until resurrection and form entry", %{
      character: character,
      talent: talent
    } do
      {cat, _events} = apply_spell(character, form(1), 1000)
      dead = Core.take_damage(cat, 1000, 2000)
      refute Aura.has_spell?(dead, talent.id)
      assert {^dead, []} = PassiveSpells.restore(dead, 2000)
      ghost = %{dead | unit: %{dead.unit | health: 1}, player: %{dead.player | flags: 0x10}}
      assert {^ghost, []} = PassiveSpells.restore(ghost, 2000)
      {alive, _events} = Death.resurrect(dead, 1.0, 3000)
      {cat, _events} = apply_spell(alive, form(1), 4000)
      assert Aura.has_spell?(cat, talent.id)
    end

    test "only self-cast form-bound effects end on leaving the form", %{character: character} do
      buff = %{passive(100, 1) | attributes: MapSet.new()}
      preserved = %{buff | id: 101, attributes: MapSet.new([:allow_while_not_shapeshifted])}
      external = %{buff | id: 102}
      {cat, _events} = apply_spell(character, form(1), 1000)
      {cat, _events} = apply_spell(cat, buff, 1000)
      {cat, _events} = apply_spell(cat, preserved, 1000)
      {cat, _events} = Aura.apply_spell(cat, 2, 60, external, 1000)
      {normal, _events} = Aura.cancel_spell(cat, form(1).id, 2000)
      refute Aura.has_spell?(normal, buff.id)
      assert Aura.has_spell?(normal, preserved.id)
      assert Aura.has_spell?(normal, external.id)
    end

    test "hidden Feline Swiftness dodge is cat-only even without its DBC stance mask", %{character: character} do
      hidden = %{passive(24_864, 0) | attributes: MapSet.new([:do_not_display])}
      character = %{character | internal: %{character.internal | spellbook: %{hidden.id => hidden}}}
      assert {^character, []} = PassiveSpells.restore(character, 1000)
      {cat, _events} = apply_spell(character, form(1), 1000)
      assert Aura.has_spell?(cat, hidden.id)
      {bear, _events} = apply_spell(cat, form(5), 2000)
      refute Aura.has_spell?(bear, hidden.id)
    end
  end

  defp character(_context) do
    talent = passive(16_944, 145)

    character = %Character{
      object: %Object{guid: 1},
      unit: %Unit{health: 100, max_health: 100, level: 60, class: 11, auras: []},
      player: %Player{},
      internal: %Internal{spells: [talent.id], spellbook: %{talent.id => talent}},
      movement_block: struct!(%MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}, MovementBlock.player_speeds())
    }

    %{character: character, talent: talent}
  end

  defp passive(id, stances) do
    %Spell{
      id: id,
      stances: stances,
      attributes: MapSet.new([:passive]),
      effects: [%Effect{type: :apply_aura, aura: :mod_crit_percent, base_points: 6}]
    }
  end

  defp form(form) do
    %Spell{id: 1000 + form, effects: [%Effect{type: :apply_aura, aura: :mod_shapeshift, misc_value: form}]}
  end

  defp apply_spell(character, spell, now), do: Aura.apply_spell(character, 1, 60, spell, now)
end
