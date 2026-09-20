defmodule ThistleTea.Game.Entity.EffectResolver.PvpTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.EffectResolver.Pvp
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Pvp, as: PvpLogic
  alias ThistleTea.Game.Guid

  describe "contacts/5" do
    test "resolves a pet attack to both players and applies the owner's flags" do
      pet = Guid.from_low_guid(:pet, 1, 7)
      rows = %{pet => %{owner_guid: 1}, 1 => %{pvp?: false}, 2 => %{pvp?: true}}
      effects = Pvp.contacts(%{}, pet, 2, :attack, metadata: &Map.get(rows, &1), now: 0)
      assert [%Effects.PvpContact{target_guid: 1} = attack, %Effects.PvpContact{target_guid: 2} = attacked] = effects
      assert attack.other.player_guid == 2
      assert attacked.other.player_guid == 1
      assert attacked.other.pvp?
      owner = EventSink.emit(character(1), attack)
      assert PvpLogic.active?(owner)
      assert PvpLogic.contested?(owner)
      assert owner.internal.in_combat
      victim = EventSink.emit(character(2), attacked)
      assert PvpLogic.active?(victim)
      refute PvpLogic.contested?(victim)
    end

    test "helping another player's totem resolves its owner's PvP state" do
      totem = Guid.from_low_guid(:mob, 5925, 1)
      rows = %{totem => %{owner_guid: 2}, 2 => %{pvp?: true, contested_pvp?: true, in_combat: true}}
      effects = Pvp.contacts(character(1), 1, totem, :assist, metadata: &Map.get(rows, &1), now: 0)
      assert [%Effects.PvpContact{target_guid: 1, role: :assist} = effect] = effects
      caster = EventSink.emit(character(1), effect)
      assert PvpLogic.contested?(caster)
      assert caster.internal.in_combat
    end

    test "ordinary PvE and self assistance produce no PvP notifications" do
      mob = Guid.from_low_guid(:mob, 1, 1)
      rows = %{mob => %{unit_flags: 0}}
      assert Pvp.contacts(character(1), 1, mob, :attack, metadata: &Map.get(rows, &1), now: 0) == []
      flagged = PvpLogic.toggle(character(1), true, 0)
      assert Pvp.contacts(flagged, 1, 1, :assist, metadata: fn _ -> nil end, now: 0) == []
    end

    test "PvP-enabling creatures flag the aggressor without contested guards" do
      mob = Guid.from_low_guid(:mob, 1, 1)
      rows = %{mob => %{unit_flags: 0x1000}}
      [effect] = Pvp.contacts(character(1), 1, mob, :attack, metadata: &Map.get(rows, &1), now: 0)
      caster = EventSink.emit(character(1), effect)
      assert PvpLogic.active?(caster)
      refute PvpLogic.contested?(caster)
    end
  end

  defp character(guid) do
    %Character{
      object: %Object{guid: guid},
      unit: %Unit{health: 100, flags: 8},
      player: %Player{flags: 0},
      internal: %Internal{}
    }
  end
end
