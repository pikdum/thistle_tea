defmodule ThistleTea.Game.Entity.Logic.MeleeSpellTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.MeleeSpell
  alias ThistleTea.Game.Spell

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
end
