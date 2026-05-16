defmodule ThistleTea.Game.Entity.Logic.AI.BT.SpellTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Spell, as: SpellBT
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
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
          casting: %Cast{
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

    test "first channel tick marks spell go as sent and advances the next tick" do
      now = Time.now()
      spell = %Spell{id: 10, attributes: MapSet.new([:channeled]), effects: []}

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{health: 100, max_health: 100},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{
          map: 0,
          casting: %Cast{
            spell: spell,
            targets: %Targets{raw: <<0::little-size(16)>>, unit_guid: 1},
            channel_ms: 8_000,
            channel_tick_ms: 1_000,
            channel_go_sent?: false,
            next_channel_tick_at: now - 1,
            ends_at: now + 8_000
          }
        }
      }

      assert {{:running, delay_ms}, mob, %Blackboard{}} = SpellBT.cast_tick(mob, Blackboard.new())
      assert delay_ms > 0
      assert mob.internal.casting.channel_go_sent? == true
      assert mob.internal.casting.next_channel_tick_at > now
    end
  end
end
