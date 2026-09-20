defmodule ThistleTea.Game.Entity.Logic.PvpTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Duel
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.AI.Tick
  alias ThistleTea.Game.Entity.Logic.Pvp

  setup [:character]

  describe "toggle/3" do
    test "projects preference and active flags without replacing other bits", %{character: character} do
      flagged = Pvp.toggle(character, true, 0)
      assert flagged.player.flags == 0x201
      assert flagged.unit.flags == 0x1008
      assert flagged.internal.broadcast_update?
      assert Pvp.active?(flagged)
      assert Pvp.active?(Pvp.tick(flagged, 600_000))

      pending = Pvp.toggle(flagged, :toggle, 600_000)
      assert pending.player.flags == 1
      assert Pvp.active?(Pvp.tick(pending, 899_999))
      expired = Pvp.tick(pending, 900_000)
      refute Pvp.active?(expired)
      assert expired.unit.flags == 8
      refute Pvp.needs_tick?(expired)
    end

    test "repeated disabling does not restart the countdown", %{character: character} do
      pending = character |> Pvp.toggle(true, 0) |> Pvp.toggle(false, 100)
      pending = Pvp.toggle(pending, false, 200_100)
      assert pending.internal.pvp.remaining_ms == 100_000
      refute Pvp.active?(Pvp.tick(pending, 300_100))
    end

    test "reenabling refreshes the full countdown", %{character: character} do
      flagged = character |> Pvp.toggle(true, 0) |> Pvp.toggle(false, 0) |> Pvp.toggle(true, 250_000)
      assert flagged.internal.pvp.remaining_ms == 300_000
    end
  end

  describe "contact/4" do
    test "attacking a flagged player marks the aggressor contested", %{character: character} do
      flagged = Pvp.contact(character, :attack, player(), 0)
      assert Pvp.active?(flagged)
      assert Pvp.contested?(flagged)
      assert (flagged.player.flags &&& 0x100) != 0
      assert Pvp.contested?(Pvp.tick(flagged, 29_999))
      refute Pvp.contested?(Pvp.tick(flagged, 30_000))
      assert Pvp.active?(Pvp.tick(flagged, 30_000))
    end

    test "being attacked refreshes PvP without contested aggression", %{character: character} do
      flagged = Pvp.contact(character, :attacked, player(), 0)
      assert Pvp.active?(flagged)
      refute Pvp.contested?(flagged)
    end

    test "both timers pause during PvP combat", %{character: character} do
      character = %{character | internal: %{character.internal | in_combat: true}}
      flagged = character |> Pvp.contact(:attack, player(), 0) |> Pvp.tick(400_000)
      assert flagged.internal.pvp.remaining_ms == 300_000
      assert flagged.internal.pvp.contested_remaining_ms == 30_000

      peaceful = %{flagged | internal: %{flagged.internal | in_combat: false}}
      peaceful = Pvp.tick(peaceful, 401_000)
      assert peaceful.internal.pvp.remaining_ms == 299_000
      assert peaceful.internal.pvp.contested_remaining_ms == 29_000
    end

    test "ordinary creature combat does not freeze a voluntary flag", %{character: character} do
      character = %{character | internal: %{character.internal | in_combat: true}}
      pending = character |> Pvp.toggle(true, 0) |> Pvp.toggle(false, 0)
      refute Pvp.active?(Pvp.tick(pending, 300_000))
    end

    test "assisting a flagged ally propagates contested combat", %{character: character} do
      assisted = %{player() | in_combat: true, contested_pvp?: true}
      flagged = Pvp.contact(character, :assist, assisted, 0)
      assert Pvp.active?(flagged)
      assert Pvp.contested?(flagged)
      assert flagged.internal.pvp.combat?
    end

    test "buffing an idle flagged ally flags without entering combat", %{character: character} do
      flagged = Pvp.contact(character, :assist, player(), 0)
      assert Pvp.active?(flagged)
      refute flagged.internal.pvp.combat?
      refute Pvp.contested?(flagged)
    end

    test "unflagged targets and own pets do not flag", %{character: character} do
      for role <- [:attack, :attacked, :assist] do
        refute Pvp.active?(Pvp.contact(character, role, %{player() | pvp?: false}, 0))
        refute Pvp.active?(Pvp.contact(character, role, %{player() | player_guid: 1}, 0))
      end
    end

    test "duels do not produce world PvP flags", %{character: character} do
      character = %{character | internal: %{character.internal | duel: %Duel{state: :started, opponent_guid: 2}}}

      for role <- [:attack, :attacked] do
        refute Pvp.active?(Pvp.contact(character, role, player(), 0))
      end
    end

    test "free-for-all combat does not produce contested aggression", %{character: character} do
      character = Pvp.territory(character, nil, %{flags: 0x80}, :normal, false, 0)
      other = %{player() | free_for_all?: true}
      refute Pvp.active?(Pvp.contact(character, :attack, other, 0))
      refute Pvp.contested?(Pvp.contact(character, :attack, other, 0))
    end

    test "PvP creatures flag attacks and combat assistance", %{character: character} do
      creature = %{player() | player_guid: nil}
      assert Pvp.active?(Pvp.contact(character, :attack, creature, 0))
      refute Pvp.contested?(Pvp.contact(character, :attack, creature, 0))
      refute Pvp.active?(Pvp.contact(character, :assist, creature, 0))
      assert Pvp.active?(Pvp.contact(character, :assist, %{creature | in_combat: true}, 0))
      refute Pvp.active?(Pvp.contact(character, :attacked, creature, 0))
    end
  end

  describe "territory/6" do
    test "enemy capitals enforce PvP on normal realms", %{character: character} do
      flagged = Pvp.territory(character, %{faction_group: 4, flags: 0x100}, nil, :normal, false, 0)
      assert Pvp.active?(flagged)
      assert flagged.internal.pvp.enforced?
      assert Pvp.active?(Pvp.tick(flagged, 400_000))

      left = Pvp.territory(flagged, %{faction_group: 0, flags: 0}, nil, :normal, false, 400_000)
      refute left.internal.pvp.enforced?
      assert Pvp.active?(Pvp.tick(left, 699_999))
      refute Pvp.active?(Pvp.tick(left, 700_000))
    end

    test "friendly capitals and contested normal zones do not force flags", %{character: character} do
      for zone <- [%{faction_group: 2, flags: 0x100}, %{faction_group: 0, flags: 0}] do
        refute Pvp.active?(Pvp.territory(character, zone, nil, :normal, false, 0))
      end
    end

    test "PvP realms enforce contested and enemy territory", %{character: character} do
      for team <- [0, 4] do
        assert Pvp.active?(Pvp.territory(character, %{faction_group: team, flags: 0}, nil, :pvp, false, 0))
      end

      for team <- [2, 6] do
        refute Pvp.active?(Pvp.territory(character, %{faction_group: team, flags: 0}, nil, :pvp, false, 0))
      end
    end

    test "battlegrounds enforce the flag independently of zone data", %{character: character} do
      assert Pvp.active?(Pvp.territory(character, nil, nil, :normal, true, 0))
    end

    test "flying over hostile territory does not enable the flag", %{character: character} do
      character = %{character | internal: %{character.internal | taxi_flight: %{}}}
      refute Pvp.active?(Pvp.territory(character, %{faction_group: 4, flags: 0x100}, nil, :normal, false, 0))
    end

    test "arena flags follow the subzone", %{character: character} do
      arena = Pvp.territory(character, nil, %{flags: 0x80}, :normal, false, 0)
      assert Pvp.free_for_all?(arena)
      assert (arena.player.flags &&& 0x80) != 0
      exited = Pvp.territory(arena, nil, %{flags: 0}, :normal, false, 1)
      refute Pvp.free_for_all?(exited)
      assert exited.player.flags == 1
    end
  end

  describe "reconnect/2" do
    test "retains countdowns without charging offline time", %{character: character} do
      flagged = character |> Pvp.contact(:attack, player(), 0) |> Pvp.tick(1_000)
      reconnected = Pvp.reconnect(flagged, 900_000)
      assert reconnected.internal.pvp.remaining_ms == 299_000
      assert reconnected.internal.pvp.contested_remaining_ms == 29_000
      assert Pvp.active?(reconnected)
      assert Pvp.contested?(reconnected)
      refute reconnected.internal.pvp.combat?
    end
  end

  describe "tick/2" do
    test "schedules idle timer expiry independently of regeneration", %{character: character} do
      flagged = character |> Pvp.toggle(true, 0) |> Pvp.toggle(false, 0)
      assert Tick.needs_tick?(flagged)
      assert Enum.any?(Tick.plan(flagged, {:running, 30_000}, 0).wakes, &(&1.source == :pvp and &1.at == 1_000))
    end

    test "death releases combat timer pauses", %{character: character} do
      flagged = Pvp.contact(character, :attack, player(), 0)
      dead = %{flagged | unit: %{flagged.unit | health: 0}, internal: %{flagged.internal | in_combat: true}}
      refute Pvp.contested?(Pvp.tick(dead, 30_000))
      refute Pvp.active?(Pvp.tick(dead, 300_000))
    end
  end

  defp player do
    %{player_guid: 2, pvp?: true, contested_pvp?: false, free_for_all?: false, in_combat: false}
  end

  defp character(_context) do
    {:ok,
     character: %Character{
       object: %Object{guid: 1},
       unit: %Unit{health: 100, max_health: 100, race: 1, flags: 8},
       player: %Player{flags: 1},
       internal: %Internal{}
     }}
  end
end
