defmodule ThistleTea.Game.OutdoorPvp.ParticipationTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Pvp
  alias ThistleTea.Game.OutdoorPvp.Participation

  describe "eligible?/2" do
    setup [:character]

    test "requires a PvP realm or an explicit PvP preference", %{character: character} do
      assert Participation.eligible?(character, :pvp)
      refute Participation.eligible?(character, :normal)
      flagged = Pvp.toggle(character, true, 1000)
      assert Participation.eligible?(flagged, :normal)
      pending = Pvp.toggle(flagged, false, 2000)
      assert Pvp.active?(pending)
      refute Participation.eligible?(pending, :normal)
    end

    test "excludes dead players, ghosts, GMs, and taxi passengers", %{character: character} do
      refute Participation.eligible?(%{character | unit: %{character.unit | health: 0}}, :pvp)
      refute Participation.eligible?(%{character | player: %{character.player | flags: 0x10}}, :pvp)
      refute Participation.eligible?(%{character | player: %{character.player | flags: 0x08}}, :pvp)
      refute Participation.eligible?(%{character | internal: %{character.internal | taxi_flight: %{}}}, :pvp)
    end

    test "excludes stealth and every invisibility type", %{character: character} do
      for type <- [:mod_stealth, :mod_invisibility] do
        holder = %Holder{auras: [%Aura{type: type, amount: 1, misc_value: 0}]}
        hidden = %{character | unit: %{character.unit | auras: [holder]}}
        refute Participation.eligible?(hidden, :pvp)
      end
    end
  end

  defp character(_context) do
    %{
      character: %Character{
        unit: %Unit{health: 100, max_health: 100, flags: 8, auras: []},
        player: %Player{flags: 0},
        internal: %Internal{}
      }
    }
  end
end
