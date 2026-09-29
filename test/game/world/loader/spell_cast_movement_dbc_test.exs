defmodule ThistleTea.Game.World.Loader.SpellCastMovementDbcTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Cast
  alias ThistleTea.Game.Core.Spell.CastMovement
  alias ThistleTea.Game.Core.Spell.Target
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  describe "load/1" do
    @tag :dbc_db
    test "retains movement, turning, hidden-channel, and self-root exceptions" do
      caster = %Character{
        internal: %Internal{},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, movement_flags: 0}
      }

      moved = %{caster | movement_block: %{caster.movement_block | position: {1.0, 0.0, 0.0, 0.0}}}
      turned = %{caster | movement_block: %{caster.movement_block | position: {0.0, 0.0, 0.0, 0.1}}}
      fireball = cast(133, caster, :preparing)
      assert CastMovement.interrupts?(moved, fireball)
      refute CastMovement.interrupts?(turned, fireball)

      for id <- [2096, 6197] do
        assert CastMovement.interrupts?(turned, cast(id, caster, :channel_tick))
      end

      refute CastMovement.interrupts?(turned, cast(5143, caster, :channel_tick))

      for id <- [24_322, 24_323] do
        channel = cast(id, caster, :channel_tick)
        assert Spell.attribute?(channel.spell, :hide_channel_bar)
        refute CastMovement.interrupts?(moved, channel)
      end

      rooted = %{moved | internal: %{moved.internal | rooted?: true}}
      waiting = cast(18_953, caster, :channel_tick)
      assert CastMovement.interrupts?(moved, waiting)
      refute CastMovement.interrupts?(rooted, waiting)

      falling = %{moved | movement_block: %{moved.movement_block | movement_flags: 0x4000}}
      refute CastMovement.interrupts?(falling, cast(7355, caster, :preparing))
      assert CastMovement.interrupts?(moved, cast(7355, caster, :preparing))
    end
  end

  defp cast(id, caster, phase) do
    id
    |> SpellLoader.load()
    |> Cast.new(Target.self(1), 1_000)
    |> CastMovement.anchor(caster)
    |> then(&%{&1 | phase: phase})
  end
end
