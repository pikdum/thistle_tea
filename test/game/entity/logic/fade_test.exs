defmodule ThistleTea.Game.Entity.Logic.FadeTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Aura.Change
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  setup [:character]

  describe "apply_spell/5" do
    test "reduces only existing hostile references", %{character: character} do
      {faded, events} = Aura.apply_spell(character, 1, 60, fade(), 1_000)
      assert Aura.has_aura?(faded, :mod_total_threat)
      assert temporary(events) == [Effects.temporary_threat(100, 7, -600), Effects.temporary_threat(200, 8, -600)]

      {_refreshed, events} = Aura.apply_spell(faded, 1, 60, fade(), 2_000)
      assert temporary(events) == []
    end

    test "out of combat casting does not create hostile references", %{character: character} do
      character = %{character | internal: %{character.internal | threat_refs: nil}}
      {_faded, events} = Aura.apply_spell(character, 1, 60, fade(), 1_000)
      assert temporary(events) == []
    end
  end

  describe "expire_due/2" do
    test "restores the modifier at the deadline", %{character: character} do
      {faded, _events} = Aura.apply_spell(character, 1, 60, fade(), 1_000)
      {faded, events} = Aura.expire_due(faded, 10_999)
      assert temporary(events) == []
      {expired, events} = Aura.expire_due(faded, 11_000)
      refute Aura.has_aura?(expired, :mod_total_threat)
      assert temporary(events) == [Effects.temporary_threat(100, 7, 0), Effects.temporary_threat(200, 8, 0)]
    end
  end

  describe "transition/2" do
    test "all removal causes restore threat", %{character: character} do
      {faded, _events} = Aura.apply_spell(character, 1, 60, fade(), 1_000)

      for cause <- [:cancelled, :dispelled, :death, :removed] do
        {_removed, events} = Aura.transition(faded, %Change{holders: [], cause: cause, now: 2_000})
        assert temporary(events) == [Effects.temporary_threat(100, 7, 0), Effects.temporary_threat(200, 8, 0)]
      end
    end
  end

  defp temporary(events), do: Enum.filter(events, &is_struct(&1, Effects.TemporaryThreat))

  defp character(_context) do
    character = %Character{
      object: %Object{guid: 1},
      unit: %Unit{health: 100, max_health: 100, level: 60, auras: []},
      player: %Player{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{threat_refs: MapSet.new([{100, 7}, {200, 8}])}
    }

    %{character: character}
  end

  defp fade do
    %Spell{
      id: 10_995,
      name: "Fade",
      duration_ms: 10_000,
      attributes: MapSet.new(),
      effects: [
        %Effect{
          index: 0,
          type: :apply_aura,
          aura: :mod_total_threat,
          base_points: -600,
          die_sides: 1,
          implicit_target_a: :caster
        }
      ]
    }
  end
end
