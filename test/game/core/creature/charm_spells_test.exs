defmodule ThistleTea.Game.Core.Creature.CharmSpellsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.CreatureSpell
  alias ThistleTea.Game.Core.Creature.CharmSpells
  alias ThistleTea.Game.Core.Creature.CharmSpells.Option
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.Internal.Pet
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Rolls
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Effect

  defp option(slot, id, availability, cooldown \\ {10_000, 10_000}) do
    {low, high} = cooldown
    %Option{slot: slot, spell: %Spell{id: id}, availability: availability, cooldown_min_ms: low, cooldown_max_ms: high}
  end

  defp mob(opts) do
    %Mob{
      internal: %Internal{
        pet: Keyword.get(opts, :pet),
        spellbook: Keyword.get(opts, :spellbook, %{1 => %Spell{id: 1}}),
        creature: %Creature{charm_spells: Keyword.get(opts, :charm_spells, [])}
      }
    }
  end

  describe "pick/2" do
    test "walks the slot's cumulative availability" do
      options = [option(0, 10, 22.0), option(0, 11, 78.0)]

      assert %Option{spell: %Spell{id: 10}} = CharmSpells.pick(options, 22.0)
      assert %Option{spell: %Spell{id: 11}} = CharmSpells.pick(options, 22.5)
      assert %Option{spell: %Spell{id: 11}} = CharmSpells.pick(options, 100.0)
    end

    test "leaves a slot empty when the roll misses every option" do
      assert CharmSpells.pick([option(0, 10, 45.0)], 60.0) == nil
      assert CharmSpells.pick([], 10.0) == nil
    end
  end

  describe "select/2" do
    test "picks one spell per slot and gives it the slot's cooldown" do
      slots = %{0 => [option(0, 10, 100.0, {9_000, 12_000})], 2 => [option(2, 12, 50.0)]}
      rolls = Rolls.fixed(charm_slot_0: 0.5, charm_cooldown_0: 11_000, charm_slot_2: 0.75)

      assert [%Spell{id: 10, recovery_time_ms: 11_000}] = CharmSpells.select(slots, rolls)

      rolls = Rolls.fixed(charm_slot_0: 0.5, charm_cooldown_0: 99_000, charm_slot_2: 0.25)

      assert [%Spell{id: 10, recovery_time_ms: 12_000}, %Spell{id: 12, recovery_time_ms: 10_000}] =
               CharmSpells.select(slots, rolls)
    end

    test "offers nothing without charm data" do
      assert CharmSpells.select(%{}, Rolls.system()) == []
    end
  end

  describe "attach/2" do
    test "adds the picked spells to the spellbook, overriding the creature's own copy" do
      mob = mob(spellbook: %{1 => %Spell{id: 1}, 10 => %Spell{id: 10, recovery_time_ms: 0}})
      attached = CharmSpells.attach(mob, [%Spell{id: 10, recovery_time_ms: 5_000}, %Spell{id: 12}])

      assert attached.internal.creature.charm_spells == [10, 12]
      assert %{1 => _, 10 => %Spell{recovery_time_ms: 5_000}, 12 => _} = attached.internal.spellbook
    end
  end

  describe "control_spells/1" do
    test "limits a charmed or possessed creature to its charm abilities" do
      spellbook = %{1 => %Spell{id: 1}, 10 => %Spell{id: 10}, 11 => %Spell{id: 11}}

      for kind <- [:charmed, :possessed] do
        controlled = mob(pet: %Pet{kind: kind}, spellbook: spellbook, charm_spells: [11, 10])

        assert controlled |> CharmSpells.control_spells() |> Map.keys() |> Enum.sort() == [10, 11]
        assert controlled |> CharmSpells.bar_spells() |> Enum.map(& &1.id) == [11, 10]
      end
    end

    test "keeps pets and possessed pets on their own spellbooks" do
      spellbook = %{1 => %Spell{id: 1}, 10 => %Spell{id: 10}}

      for pet <- [%Pet{kind: :hunter}, %Pet{kind: :hunter, possessed?: true, possession_original_kind: :hunter}] do
        assert CharmSpells.control_spells(mob(pet: pet, spellbook: spellbook, charm_spells: [10])) == spellbook
      end
    end

    test "never offers spells that charm or possess" do
      spellbook = %{
        10 => %Spell{id: 10, effects: [%Effect{aura: :mod_charm}]},
        11 => %Spell{id: 11, effects: [%Effect{aura: :mod_possess}]},
        12 => %Spell{id: 12, attributes: MapSet.new([:passive])}
      }

      controlled = mob(pet: %Pet{kind: :charmed}, spellbook: spellbook, charm_spells: [10, 11, 12])

      assert controlled |> CharmSpells.control_spells() |> Map.keys() == [12]
      assert CharmSpells.bar_spells(controlled) == []
    end
  end

  describe "entries/1" do
    test "aims harmful abilities at the victim and the rest at the creature" do
      spellbook = %{10 => %Spell{id: 10, effects: [%Effect{type: :school_damage}]}, 11 => %Spell{id: 11}}
      controlled = mob(pet: %Pet{kind: :charmed}, spellbook: spellbook, charm_spells: [10, 11])

      assert [%CreatureSpell{spell_id: 10, cast_target: :victim}, %CreatureSpell{spell_id: 11, cast_target: :self}] =
               CharmSpells.entries(controlled)
    end
  end
end
