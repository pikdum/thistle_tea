defmodule ThistleTea.Game.Core.Spell.CastMovementTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Cast
  alias ThistleTea.Game.Core.Spell.CastMovement
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.Target

  setup [:caster]

  describe "interrupts?/2" do
    test "compares each axis with the original cast position", %{caster: caster, cast: cast} do
      for position <- [{0.5, 0.5, 0.5, 0.0}, {-0.5, -0.5, -0.5, 0.0}] do
        refute CastMovement.interrupts?(move(caster, position), cast)
      end

      for position <- [{0.5001, 0.0, 0.0, 0.0}, {0.0, -0.5001, 0.0, 0.0}, {0.0, 0.0, 0.5001, 0.0}] do
        assert CastMovement.interrupts?(move(caster, position), cast)
      end

      refute CastMovement.interrupts?(flags(caster, 1), cast)
      refute CastMovement.interrupts?(move(caster, {0.0, 0.0, 0.0, 1.0}), cast)
    end

    test "honors preparation flags and cast exemptions", %{caster: caster, cast: cast} do
      moved = move(caster, {2.0, 0.0, 0.0, 0.0})

      for exempt <- [
            %{cast | triggered?: true},
            %{cast | cast_time_ms: 0},
            %{cast | phase: :impact},
            %{cast | spell: %{cast.spell | interrupt_flags: 0, aura_interrupt_flags: 8, channel_interrupt_flags: 8}},
            %{cast | spell: %{cast.spell | attributes: MapSet.new([:on_next_swing])}},
            %{cast | spell: %{cast.spell | id: 75, attributes: MapSet.new([:uses_ranged_slot, :auto_repeat])}},
            %{cast | spell: %{cast.spell | attributes: MapSet.new([:hide_channel_bar])}}
          ] do
        refute CastMovement.interrupts?(moved, exempt)
      end

      refute CastMovement.interrupts?(%Mob{movement_block: moved.movement_block}, cast)
      refute CastMovement.interrupts?(moved, %{cast | movement_origin: nil})
    end

    test "uses transport-relative distance and orientation", %{caster: caster, cast: cast} do
      caster = board(caster, 77, {0.0, 0.0, 0.0, 0.0})
      cast = CastMovement.anchor(cast, caster)
      moved_ship = move(caster, {100.0, 200.0, 300.0, 1.0})
      refute CastMovement.interrupts?(moved_ship, cast)
      refute CastMovement.interrupts?(board(moved_ship, 77, {0.5, 0.0, 0.0, 0.0}), cast)
      assert CastMovement.interrupts?(board(moved_ship, 77, {0.6, 0.0, 0.0, 0.0}), cast)
      assert CastMovement.interrupts?(board(moved_ship, 78, {0.0, 0.0, 0.0, 0.0}), cast)

      assert CastMovement.interrupts?(
               %{caster | movement_block: MovementBlock.clear_transport(caster.movement_block)},
               cast
             )

      channel = %{cast | phase: :channel_tick, spell: %{cast.spell | channel_interrupt_flags: 0x10}}
      refute CastMovement.interrupts?(moved_ship, channel)
      assert CastMovement.interrupts?(board(moved_ship, 77, {0.0, 0.0, 0.0, 0.1}), channel)
    end

    test "channel movement can be requested by any of the three flag fields", %{caster: caster, cast: cast} do
      moved = move(caster, {1.0, 0.0, 0.0, 0.0})
      spell = %{cast.spell | interrupt_flags: 0}
      channel = %{cast | phase: :channel_tick, spell: spell}
      refute CastMovement.interrupts?(moved, channel)

      for spell <- [
            %{spell | interrupt_flags: 1},
            %{spell | aura_interrupt_flags: 8},
            %{spell | channel_interrupt_flags: 8}
          ] do
        assert CastMovement.interrupts?(moved, %{channel | spell: spell})
      end
    end

    test "turning is channel-specific and jumping interrupts even hidden channels", %{caster: caster, cast: cast} do
      channel = %{cast | phase: :channel_tick, spell: %{cast.spell | channel_interrupt_flags: 0x10}}
      turned = move(caster, {0.0, 0.0, 0.0, 0.1})
      assert CastMovement.interrupts?(turned, channel)
      refute CastMovement.interrupts?(turned, %{channel | spell: %{channel.spell | channel_interrupt_flags: 8}})
      refute CastMovement.interrupts?(flags(caster, 0x10), channel)
      refute CastMovement.interrupts?(flags(caster, 0x4000), channel)

      hidden = %{channel | spell: %{channel.spell | attributes: MapSet.new([:hide_channel_bar])}}
      refute CastMovement.interrupts?(move(caster, {1.0, 0.0, 0.0, 0.0}), hidden)
      assert CastMovement.interrupts?(flags(caster, 0x2000), hidden)
      assert CastMovement.interrupts?(flags(caster, 0x6000), hidden)
      assert CastMovement.interrupts?(turned, hidden)
    end

    test "self roots retain a channel through movement before root acknowledgment", %{caster: caster, cast: cast} do
      moved = move(caster, {1.0, 0.0, 0.0, 0.0})
      rooted = %{moved | internal: %{moved.internal | rooted?: true}}

      for aura <- [:mod_root, :mod_stun] do
        effect = %Effect{type: :apply_aura, aura: aura, implicit_target_a: :caster}
        channel = %{cast | phase: :channel_tick, spell: %{cast.spell | effects: [effect]}}
        refute CastMovement.interrupts?(rooted, channel)
        assert CastMovement.interrupts?(moved, channel)
        assert CastMovement.interrupts?(flags(rooted, 0x2000), channel)
        other_target = %{channel | spell: %{channel.spell | effects: [%{effect | implicit_target_a: :target_enemy}]}}
        assert CastMovement.interrupts?(rooted, other_target)
      end
    end

    test "only first-effect stuck recovery can finish during a long fall", %{caster: caster, cast: cast} do
      falling = caster |> move({1.0, 0.0, -5.0, 0.0}) |> flags(0x4000)
      assert CastMovement.interrupts?(falling, cast)
      stuck = %{cast | spell: %{cast.spell | effects: [%Effect{index: 0, type: :stuck}]}}
      refute CastMovement.interrupts?(falling, stuck)
      assert CastMovement.interrupts?(flags(falling, 0x2000), stuck)
      assert CastMovement.interrupts?(flags(falling, 0), stuck)
      later = %{stuck | spell: %{stuck.spell | effects: [%Effect{index: 1, type: :stuck}]}}
      assert CastMovement.interrupts?(falling, later)
    end
  end

  defp move(caster, position), do: %{caster | movement_block: %{caster.movement_block | position: position}}
  defp flags(caster, flags), do: %{caster | movement_block: %{caster.movement_block | movement_flags: flags}}

  defp board(caster, guid, position),
    do: %{caster | movement_block: %{caster.movement_block | transport_guid: guid, transport_position: position}}

  defp caster(_context) do
    caster = %Character{
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, movement_flags: 0},
      internal: %Internal{}
    }

    spell = %Spell{id: 900_853, cast_time_ms: 1_000, interrupt_flags: 1}
    cast = spell |> Cast.new(Target.self(1), 1_000) |> CastMovement.anchor(caster)
    %{caster: caster, cast: cast}
  end
end
