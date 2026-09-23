defmodule ThistleTea.Game.Entity.Logic.CorpseReclaimTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.CorpseReclaim, as: Reclaim
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.CorpseReclaim
  alias ThistleTea.Game.Entity.Logic.Death

  setup [:build_character]

  describe "on_damage/3" do
    test "counts lethal transitions once across damage sources", %{character: character} do
      for opts <- [[source: 2], [environmental?: true], [school: :shadow]] do
        hurt = Core.take_damage(character, 1, 0, opts)
        assert hurt.internal.corpse_reclaim.expires_at == nil
        dead = Core.take_damage(hurt, 99, 1_000, opts)
        assert dead.internal.corpse_reclaim.expires_at == 301_000
        repeated = Core.take_damage(dead, 100, 2_000, opts)
        assert repeated.internal.corpse_reclaim == dead.internal.corpse_reclaim
      end
    end

    test "preserves non-player entities" do
      mob = %Mob{}
      assert CorpseReclaim.on_damage(mob, 100, 0) == mob
    end

    test "escalates to two minutes and retains history after resurrection", %{character: character} do
      Enum.reduce([{0, 30_000}, {60_000, 60_000}, {150_000, 120_000}, {300_000, 120_000}], character, fn
        {now, expected_delay}, character ->
          dead = Core.take_damage(character, 100, now)
          released = CorpseReclaim.release(dead, now + 1_000)
          assert CorpseReclaim.delay_ms(released.internal.corpse_reclaim, now + 1_000) == expected_delay
          {revived, _events} = Death.resurrect(released, 1.0, now + expected_delay + 1_000)
          assert revived.internal.corpse_reclaim.expires_at == dead.internal.corpse_reclaim.expires_at
          assert revived.internal.corpse_reclaim.released_at == nil
          revived
      end)
    end

    test "decays in five-minute steps and resets after the history expires", %{character: character} do
      character = put_in(character.internal.corpse_reclaim, %Reclaim{expires_at: 900_000})
      assert CorpseReclaim.delay_ms(character.internal.corpse_reclaim, 300_000) == 120_000
      assert CorpseReclaim.delay_ms(character.internal.corpse_reclaim, 300_001) == 60_000
      assert CorpseReclaim.delay_ms(character.internal.corpse_reclaim, 600_001) == 30_000
      dead = Core.take_damage(character, 100, 900_000)
      assert dead.internal.corpse_reclaim.expires_at == 1_200_000
      assert CorpseReclaim.delay_ms(dead.internal.corpse_reclaim, 901_000) == 30_000
    end
  end

  describe "remaining_ms/2" do
    test "retains the release countdown for reconnect and clamps expired time" do
      reclaim = %Reclaim{expires_at: 600_000, released_at: 10_000}
      assert CorpseReclaim.remaining_ms(reclaim, 10_000) == 60_000
      assert CorpseReclaim.remaining_ms(reclaim, 35_000) == 35_000
      assert CorpseReclaim.remaining_ms(reclaim, 70_000) == 0
      assert CorpseReclaim.remaining_ms(reclaim, 90_000) == 0
      assert CorpseReclaim.remaining_ms(%Reclaim{}, 90_000) == 0
    end
  end

  describe "ready?/2" do
    test "requires spirit release and enforces the deadline including negative clocks" do
      refute CorpseReclaim.ready?(%Reclaim{expires_at: 300_000}, 1_000_000)
      reclaim = %Reclaim{expires_at: -700_000, released_at: -999_000}
      refute CorpseReclaim.ready?(reclaim, -969_001)
      assert CorpseReclaim.ready?(reclaim, -969_000)
    end

    test "uses the live decay tier when validating a reclaim" do
      reclaim = %Reclaim{expires_at: 600_000, released_at: 299_000}
      assert CorpseReclaim.remaining_ms(reclaim, 329_000) == 30_000
      assert CorpseReclaim.ready?(reclaim, 329_000)
    end
  end

  describe "clear_release/1" do
    test "spell resurrection clears the current release while preserving history", %{character: character} do
      reclaim = %Reclaim{expires_at: 600_000, released_at: 10_000}
      character = put_in(character.internal.corpse_reclaim, reclaim)
      {revived, _events} = Death.resurrect_with(character, 50, 20, 11_000)
      assert revived.internal.corpse_reclaim == %{reclaim | released_at: nil}
      refute CorpseReclaim.ready?(revived.internal.corpse_reclaim, 1_000_000)
    end
  end

  defp build_character(_context) do
    character = %Character{
      object: %Object{guid: 1},
      unit: %Unit{health: 100, max_health: 100, max_power1: 80, level: 10, auras: []},
      player: %Player{flags: 0},
      internal: %Internal{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    %{character: character}
  end
end
