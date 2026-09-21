defmodule ThistleTea.Game.Entity.Logic.EmoteTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Emote, as: Definition
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Emote
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target

  setup [:character]

  describe "text/3" do
    test "separates persistent animations, one-shots and client-controlled poses", %{character: c} do
      assert Emote.text(c, %Definition{id: 10, persistent?: true}, 1_000).internal.events ==
               [%Effects.EmoteState{emote_id: 10}]

      assert Emote.text(c, %Definition{id: 3}, 1_000).internal.events == [%Effects.EmoteAnimation{emote_id: 3}]

      for id <- [0, 12, 13, 68] do
        assert Emote.text(c, %Definition{id: id, persistent?: true}, 1_000) == c
      end
    end

    test "animation removes Feign Death through the aura transition", %{character: c} do
      spell = buff(5384, :feign_death, 0x20)
      {feigning, _} = Aura.apply_spell(c, 1, 50, spell, 1_000)
      assert feigning.unit.stand_state == 0
      assert feigning.unit.dynamic_flags == 0x28
      assert Enum.any?(feigning.unit.auras, &(&1.spell.id == 5384))

      standing = Emote.command(feigning, 0, 2_000)
      assert standing.unit.auras == []
      assert standing.unit.stand_state == 0
      assert standing.unit.dynamic_flags == 0x08
      assert standing.unit.health == feigning.unit.health
      assert Enum.any?(standing.internal.events, &is_struct(&1, Effects.EmoteAnimation))
    end

    test "ignores dead, ghost and animation-blocked actors", %{character: c} do
      actors = [
        %{c | unit: %{c.unit | health: 0}},
        %{c | player: %{c.player | flags: 0x10}},
        %{c | unit: %{c.unit | flags: 0x20000000}}
      ]

      for actor <- actors do
        refute Emote.allowed?(actor)
        assert Emote.text(actor, %Definition{id: 10, persistent?: true}, 1_000) == actor
        assert Emote.command(actor, 3, 1_000) == actor
      end
    end
  end

  describe "command/3" do
    test "rejects forged animations and clears a persistent pose on cancel", %{character: c} do
      dancing = Emote.set_state(c, 10)
      assert Emote.command(dancing, 10, 1_000) == dancing
      assert Emote.command(dancing, 9999, 1_000) == dancing
      cancelled = Emote.command(dancing, 0, 1_000)
      assert cancelled.unit.npc_emote_state == 0
      assert cancelled.internal.events == [%Effects.EmoteAnimation{emote_id: 0}]
    end

    test "interrupts only animation-sensitive channels and removes their owned aura", %{character: c} do
      for flags <- [0x20, 0] do
        spell = %{buff(100, :dummy, 0) | channel_interrupt_flags: flags, attributes: MapSet.new([:channeled])}
        {channeling, _} = Aura.apply_spell(c, 1, 50, spell, 1_000)
        cast = %{Cast.new(spell, Target.self(1), 1_000) | phase: :channel_tick, channel_ms: 10_000}
        channeling = %{channeling | internal: %{channeling.internal | casting: cast}}
        result = Emote.command(channeling, 3, 2_000)

        if flags == 0x20 do
          assert result.internal.casting == nil
          assert result.unit.auras == []
          assert Enum.any?(result.internal.events, &is_struct(&1, Effects.ChannelUpdate))
        else
          assert result.internal.casting == cast
          assert result.unit.auras == channeling.unit.auras
        end
      end
    end
  end

  describe "stand/3" do
    test "accepts only client postures and acknowledges each transition", %{character: c} do
      for posture <- [1, 3, 8] do
        posed = Emote.stand(c, posture, 1_000)
        assert posed.unit.stand_state == posture
        assert posed.internal.events == [Effects.stand_state(posture)]
        assert Emote.stand(posed, 0, 2_000).unit.stand_state == 0
      end

      for invalid <- [2, 4, 5, 6, 7, 9, 255, 256], do: assert(Emote.stand(c, invalid, 1_000) == c)
      blocked = %{c | unit: %{c.unit | flags: 0x20000000}}
      assert Emote.stand(blocked, 1, 1_000) == blocked
    end

    test "standing cancels food while sitting and sleeping preserve its interrupt rule", %{character: c} do
      {eating, _} = Aura.apply_spell(c, 1, 50, buff(200, :periodic_heal, 0x40000), 1_000)
      assert eating.unit.stand_state == 1
      assert Emote.stand(eating, 1, 2_000).unit.auras != []
      assert Emote.stand(eating, 3, 2_000).unit.auras != []
      assert Emote.stand(eating, 0, 2_000).unit.auras == []
    end
  end

  describe "move/4" do
    test "stationary packets preserve poses and translation clears persistent animations", %{character: c} do
      dancing = Emote.set_state(c, 10)
      sitting = %{dancing | unit: %{dancing.unit | stand_state: 1}}
      assert Emote.move(sitting, false, false, 1_000) == sitting
      turning = Emote.move(sitting, false, true, 1_000)
      assert turning.unit.stand_state == 0
      assert turning.unit.npc_emote_state == 10
      moved = Emote.move(dancing, true, true, 1_000)
      assert moved.unit.npc_emote_state == 0
    end
  end

  describe "reset/1" do
    test "Feign Death replacement preserves the pose and the final removal restores standing", %{character: c} do
      spell = buff(5384, :feign_death, 0x20)
      {feigning, _} = Aura.apply_spell(c, 1, 50, spell, 1_000)
      {refreshed, events} = Aura.apply_spell(feigning, 1, 50, spell, 2_000)
      assert refreshed.unit.stand_state == 0
      assert refreshed.unit.dynamic_flags == 0x28
      refute Enum.any?(events, &is_struct(&1, Effects.DropNearbyThreat))

      for transition <- [&Aura.remove_spells(&1, [5384], 3_000), &Aura.expire_due(&1, 12_000)] do
        {standing, events} = transition.(refreshed)
        assert standing.unit.stand_state == 0
        assert standing.unit.dynamic_flags == 0x08
        assert standing.unit.auras == []
        refute Enum.any?(events, &is_struct(&1, Effects.StandState))
      end
    end

    test "death and reconnect clear animation and posture state", %{character: c} do
      dancing = %{Emote.set_state(c, 10) | unit: %{c.unit | npc_emote_state: 10, stand_state: 8}}
      dead = Core.take_damage(dancing, 200, 1_000)
      assert dead.unit.health == 0
      assert dead.unit.npc_emote_state == 0
      assert dead.unit.stand_state == 0
      reset = Emote.reset(dancing)
      assert reset.unit.npc_emote_state == 0
      assert reset.unit.stand_state == 0
      assert Emote.reset(reset) == reset
    end
  end

  defp character(_context) do
    %{
      character: %Character{
        object: %Object{guid: 1},
        player: %Player{flags: 0},
        unit: %Unit{
          health: 100,
          max_health: 100,
          level: 50,
          auras: [],
          flags: 0,
          dynamic_flags: 0x08,
          stand_state: 0,
          npc_emote_state: 0
        },
        internal: %Internal{},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }
    }
  end

  defp buff(id, aura, mask) do
    %Spell{
      id: id,
      duration_ms: 10_000,
      aura_interrupt_flags: mask,
      effects: [%Effect{index: 0, type: :apply_aura, aura: aura, base_points: 1}]
    }
  end
end
