defmodule ThistleTea.Game.Entity.Logic.AI.BT.SpellTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Spell, as: SpellBT
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Targets
  alias ThistleTea.Game.Time

  describe "start_cast/3" do
    test "queues on-next-swing spells instead of starting a cast" do
      spell = %Spell{id: 78, attributes: MapSet.new([:on_next_swing])}
      mob = %Mob{internal: %Internal{}}

      mob = SpellBT.start_cast(mob, spell, %Targets{raw: <<0::little-size(16)>>})

      assert mob.internal.next_swing_spell == spell
      assert mob.internal.casting == nil
    end

    test "initializes channel tick scheduling for channeled spells" do
      spell = %Spell{
        id: 10,
        duration_ms: 8_000,
        attributes: MapSet.new([:channeled]),
        effects: [%Effect{amplitude_ms: 2_000}]
      }

      mob = %Mob{internal: %Internal{}}

      mob = SpellBT.start_cast(mob, spell, %Targets{raw: <<0::little-size(16)>>})

      assert mob.internal.casting.channel_ms == 8_000
      assert mob.internal.casting.channel_tick_ms == 2_000
      assert is_integer(mob.internal.casting.next_channel_tick_at)
    end
  end

  describe "cast_tick/2" do
    test "ending a channel clears casting without applying a final spell hit" do
      spell = %Spell{id: 10, attributes: MapSet.new([:channeled])}

      mob = %Mob{
        internal: %Internal{
          casting: %{
            spell: spell,
            targets: %Targets{raw: <<0::little-size(16)>>},
            channel_ms: 8_000,
            ends_at: Time.now() - 1
          }
        }
      }

      assert {:success, mob, %Blackboard{}} = SpellBT.cast_tick(mob, Blackboard.new())
      assert mob.internal.casting == nil
    end
  end
end
