defmodule ThistleTea.Game.Entity.Logic.FallingTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Falling
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Spell

  describe "update/3" do
    setup [:character]

    test "damages once on landing using the highest observed point", %{character: character} do
      character = move(character, 30.0, 0x2000)
      character = move(character, 35.0, 0x2000)
      character = move(character, 20.0, 0x4000)
      landed = land(character, 5.0)

      assert landed.unit.health == 703
      assert landed.internal.fall == nil
      assert landed.internal.broadcast_update?
      assert [%Effects.EnvironmentalDamage{type: :fall, damage: 297}] = landed.internal.events
      assert land(landed, 5.0) == landed
    end

    test "ignores short drops, short falls, ordinary jumps and untracked landings", %{character: character} do
      for {height, flags, time} <- [{14.0, 0x4000, 2000}, {40.0, 0x4000, 1228}, {40.0, 0x2000, 2000}] do
        landed = character |> move(height, flags) |> land(0.0, time)
        assert landed.unit.health == 1000
        assert landed.internal.events == []
      end

      assert land(character, -100.0).unit.health == 1000
    end

    test "caps lethal damage at maximum health and follows the death transition", %{character: character} do
      landed = character |> move(200.0, 0x4000) |> land(0.0)

      assert landed.unit.health == 0
      assert landed.internal.in_combat == false
      assert landed.internal.fall == nil
      assert %Effects.EnvironmentalDamage{type: :fall, damage: 1000} in landed.internal.events
      assert %Effects.MovementRootChanged{rooted?: true} in landed.internal.events
      assert %Effects.MovementStopped{} in landed.internal.events
    end

    test "safe fall reduces the effective height", %{character: character} do
      character = with_aura(character, :safe_fall, 10)
      landed = character |> move(30.0, 0x4000) |> land(0.0)
      assert landed.unit.health == 883

      landed = character |> move(20.0, 0x4000) |> land(0.0)
      assert landed.unit.health == 1000
    end

    test "slow fall, hover and physical immunity prevent damage", %{character: character} do
      for type <- [:feather_fall, :hover, :school_immunity, :damage_immunity] do
        protected = with_aura(character, type, 0, 1)
        landed = protected |> move(200.0, 0x4000) |> land(0.0)
        assert landed.unit.health == 1000
        assert landed.internal.events == []
      end
    end

    test "applying slow fall midair discards the previous fall", %{character: character} do
      falling = move(character, 200.0, 0x4000)
      protected = falling |> with_aura(:feather_fall, 0) |> move(20.0, 0x4000)
      unprotected = %{protected | unit: %{protected.unit | auras: []}}
      landed = unprotected |> move(10.0, 0x4000) |> land(0.0)
      assert landed.unit.health == 1000
    end

    test "absorption and damage splitting do not protect against falls", %{character: character} do
      for type <- [:school_absorb, :split_damage_percent] do
        shielded = with_aura(character, type, 1000, 1)
        landed = shielded |> move(30.0, 0x4000) |> land(0.0)
        assert landed.unit.health == 703
        assert landed.unit.auras == shielded.unit.auras
        refute Enum.any?(landed.internal.events, &match?(%Effects.DeliverSpell{}, &1))
      end
    end

    test "physical damage reduction applies once", %{character: character} do
      landed = character |> with_aura(:mod_damage_percent_taken, -50, 1) |> move(30.0, 0x4000) |> land(0.0)
      assert landed.unit.health == 852
      assert [%Effects.EnvironmentalDamage{damage: 148}] = landed.internal.events
    end

    test "dead players, ghosts and god mode cannot take fall damage", %{character: character} do
      for protected <- [
            %{character | unit: %{character.unit | health: 0}},
            %{character | player: %{character.player | flags: 0x10}},
            %{character | internal: %{character.internal | godmode: true}}
          ] do
        landed = protected |> move(200.0, 0x4000) |> land(0.0)
        assert landed.unit.health == protected.unit.health
        assert landed.internal.events == []
      end
    end

    test "swimming and grounded movement reset a fall", %{character: character} do
      for flags <- [0, 0x00200000] do
        landed = character |> move(200.0, 0x4000) |> move(20.0, flags) |> land(0.0)
        assert landed.unit.health == 1000
      end

      landed = character |> move(200.0, 0x4000) |> Falling.update(:swim, 1000) |> land(0.0)
      assert landed.unit.health == 1000
    end

    test "tracks transport-local height and ignores a change of transport", %{character: character} do
      character = on_transport(character, 7, 30.0)
      falling = move(character, 200.0, 0x02004000)
      landed = falling |> on_transport(7, 0.0) |> land(200.0)
      assert landed.unit.health == 703

      landed = falling |> on_transport(8, 0.0) |> land(0.0)
      assert landed.unit.health == 1000

      landed = falling |> on_transport(nil, 0.0) |> land(0.0)
      assert landed.unit.health == 1000
    end

    test "accepts a fall starting at zero or negative elevation", %{character: character} do
      landed = character |> move(0.0, 0x4000) |> land(-30.0)
      assert landed.unit.health == 703
    end
  end

  describe "reset/1" do
    setup [:character]

    test "discards the fall before relocation", %{character: character} do
      landed = character |> move(200.0, 0x4000) |> Falling.reset() |> land(0.0)
      assert landed.unit.health == 1000
    end

    test "teleporting clears tracked height", %{character: character} do
      falling = move(character, 200.0, 0x4000)
      {teleported, _transition} = Movement.teleport(falling, {0.0, 0.0, 0.0, 0.0}, 2000)
      assert teleported.internal.fall == nil
      assert land(teleported, 0.0).unit.health == 1000
    end

    test "server-driven movement clears tracked height", %{character: character} do
      moving =
        character
        |> move(200.0, 0x4000)
        |> Movement.start_timed_path([{0.0, 0.0, 0.0}], 1000, 1000)

      assert moving.internal.fall == nil
    end
  end

  defp character(_context) do
    [
      character: %Character{
        object: %Object{guid: 1},
        player: %Player{flags: 0},
        unit: %Unit{health: 1000, max_health: 1000, level: 10, auras: []},
        internal: %Internal{},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, movement_flags: 0}
      }
    ]
  end

  defp move(character, z, flags) do
    %{character | movement_block: %{character.movement_block | position: {0.0, 0.0, z, 0.0}, movement_flags: flags}}
    |> Falling.update(:move, 1000)
  end

  defp land(character, z, time \\ 2000) do
    %{
      character
      | movement_block: %{character.movement_block | position: {0.0, 0.0, z, 0.0}, movement_flags: 0, fall_time: time}
    }
    |> Falling.update(:land, 2000)
  end

  defp on_transport(character, guid, z) do
    %{
      character
      | movement_block: %{character.movement_block | transport_guid: guid, transport_position: {0.0, 0.0, z, 0.0}}
    }
  end

  defp with_aura(character, type, amount, misc \\ 0) do
    holder = %Holder{spell: %Spell{id: 1}, caster_guid: 2, auras: [%Aura{type: type, amount: amount, misc_value: misc}]}
    %{character | unit: %{character.unit | auras: [holder]}}
  end
end
