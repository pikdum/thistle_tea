defmodule ThistleTea.Game.Entity.Logic.MeleeSpellTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.MeleeSpell
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  describe "queue_next_swing/2" do
    test "stores an on-next-swing spell in internal state" do
      spell = %Spell{id: 78, name: "Heroic Strike"}
      mob = %Mob{internal: %Internal{}}

      mob = MeleeSpell.queue_next_swing(mob, spell)

      assert mob.internal.next_swing_spell == spell
    end
  end

  describe "consume_next_swing/1" do
    test "returns and clears the queued spell" do
      spell = %Spell{id: 78, name: "Heroic Strike"}
      mob = %Mob{internal: %Internal{next_swing_spell: spell}}

      {mob, consumed} = MeleeSpell.consume_next_swing(mob)

      assert consumed == spell
      assert mob.internal.next_swing_spell == nil
    end
  end

  describe "apply_to_attack/2" do
    test "adds queued weapon damage and spell metadata to the melee attack" do
      spell = %Spell{
        id: 78,
        name: "Heroic Strike",
        school: :physical,
        effects: [%Effect{type: :weapon_damage_noschool, base_points: 10, die_sides: 0}]
      }

      attack = MeleeSpell.apply_to_attack(%{min_damage: 2, max_damage: 4}, spell)

      assert attack.min_damage == 12
      assert attack.max_damage == 14
      assert attack.spell_id == 78
      assert attack.queued_spell_id == 78
      assert attack.spell_school_mask == 1
    end
  end
end
