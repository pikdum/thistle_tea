defmodule ThistleTea.Game.Entity.Logic.InsigniaTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Corpse
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Insignia
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastValidation
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.WorldRef

  setup [:characters]

  describe "prepare/2" do
    test "marks only dead battleground players and clears the flag on release and resurrection", %{victim: victim} do
      refute Insignia.available?(victim)
      assert Insignia.prepare(victim, false) == victim
      prepared = Insignia.prepare(victim, true)
      assert Insignia.available?(prepared)
      assert Corpse.build(prepared, []).corpse.flags == 0x24

      {ghost, _events} = Death.release_spirit(prepared, [], 10)
      refute Insignia.available?(ghost)
      assert ghost.unit.flags == 0x08
      {alive, _events} = Death.resurrect(prepared, 1.0, 10)
      refute Insignia.available?(alive)
      assert alive.unit.flags == 0x08
      assert Insignia.prepare(alive, true) == alive
    end
  end

  describe "validate/2" do
    test "admits enemy bodies and rejects stale, hidden, distant, and foreign-copy snapshots", %{
      caster: caster,
      body: body
    } do
      assert Insignia.validate(caster, body) == :ok
      assert Insignia.validate(caster, %{body | team: :alliance}) == {:error, :target_friendly}
      assert Insignia.validate(caster, %{body | available?: false}) == {:error, :target_unskinnable}
      assert Insignia.validate(caster, %{body | visible?: false}) == {:error, :bad_targets}
      assert Insignia.validate(caster, %{body | los?: false}) == {:error, :line_of_sight}

      assert Insignia.validate(caster, %{body | position: {caster.internal.world, 10.01, 0.0, 0.0}}) ==
               {:error, :out_of_range}

      assert Insignia.validate(caster, %{body | position: {WorldRef.instance(529, 2), 0.0, 0.0, 0.0}}) ==
               {:error, :bad_targets}

      assert Insignia.validate(put_in(caster.unit.health, 0), body) == {:error, :caster_dead}
      assert Insignia.validate(caster, :unknown) == {:error, :bad_targets}
    end

    test "cast validation uses corpse eligibility for Remove Insignia", %{
      caster: caster,
      body: body
    } do
      spell = %Spell{id: 22_027, effects: [%Effect{type: :remove_insignia}]}
      assert CastValidation.validate_target(caster, spell, Target.unit(2), body) == :ok

      assert CastValidation.validate_target(caster, spell, Target.unit(2), %{body | available?: false}) ==
               {:error, :target_unskinnable}
    end
  end

  describe "gold/2" do
    test "matches the victim-level formula and random bounds" do
      assert Insignia.gold(10, 50) == 3
      assert Insignia.gold(10, 150) == 9
      assert Insignia.gold(60, 50) == 280
      assert Insignia.gold(60, 150) == 840
    end
  end

  defp characters(_context) do
    world = WorldRef.instance(529, 1)

    caster = %Character{
      object: %Object{guid: 1},
      unit: %Unit{health: 100, max_health: 100, race: 1, flags: 0},
      player: %Player{flags: 0},
      internal: %Internal{world: world},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    victim = %{
      caster
      | object: %Object{guid: 2},
        unit: %{caster.unit | health: 0, race: 2, gender: 0, level: 60, flags: 0x08},
        player: %{caster.player | skin: 0, face: 0, hair_style: 0, hair_color: 0, facial_hair: 0}
    }

    body = %{position: {world, 5.0, 0.0, 0.0}, team: :horde, available?: true, visible?: true, los?: true}
    %{caster: caster, victim: victim, body: body}
  end
end
