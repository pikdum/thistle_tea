defmodule ThistleTea.Game.Core.Honor.CombatTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Duel
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Honor.Combat
  alias ThistleTea.Game.Core.Honor.Damage
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.World.Entity.EffectResolver.Honor, as: HonorResolver

  setup [:character]

  describe "damage reception" do
    test "records damage after absorbs and includes overkill exactly once", %{character: character} do
      shield = %Holder{spell: %Spell{id: 17}, auras: [%Aura{type: :school_absorb, amount: 20, misc_value: 127}]}
      character = %{character | unit: %{character.unit | auras: [shield]}}
      character = Entity.take_damage(character, 40, 1000, source: 1)
      {[first], character} = honor_effects(character)
      assert first.damage == 20
      {character, nil} = receive_damage(character, first)
      assert character.internal.honor_damage.by_player == %{1 => 20}

      character = Entity.take_damage(character, 120, 2000, source: 3)
      {[lethal], character} = honor_effects(character)
      assert lethal.damage == 120
      assert lethal.lethal?
      {character, history} = receive_damage(character, lethal)
      assert history.by_player == %{1 => 20, 3 => 120}
      assert character.internal.honor_damage == %Damage{}
      assert {[], _character} = character |> Entity.take_damage(1, 3000, source: 3) |> honor_effects()
    end

    test "captures Honorless Target before death cleanup", %{character: character} do
      holder = %Holder{spell: %Spell{id: 2479}, auras: [%Aura{type: :honorless_target}]}
      character = %{character | unit: %{character.unit | auras: [holder]}}
      character = Entity.take_damage(character, 200, 1000, source: 1)
      {[effect], character} = honor_effects(character)
      assert effect.honorless?
      assert character.unit.auras == []
      {character, nil} = receive_damage(character, effect)
      assert character.internal.honor_damage == %Damage{}
    end

    test "duel defeat cannot produce a lethal honor request", %{character: character} do
      duel = %Duel{opponent_guid: 1, state: :started}
      character = %{character | internal: %{character.internal | duel: duel}}
      {[effect], character} = character |> Entity.take_damage(200, 1000, source: 1) |> honor_effects()
      assert character.unit.health == 1
      refute effect.lethal?
    end

    test "self-inflicted death excludes self damage but credits recent opponents", %{character: character} do
      history = %Damage{by_player: %{1 => 20}, last_damage_at: 500}
      character = %{character | internal: %{character.internal | honor_damage: history}}
      {[effect], character} = character |> Entity.take_damage(200, 1000, source: 2) |> honor_effects()
      {character, history} = receive_damage(character, effect)
      assert history.by_player == %{1 => 20}
      assert character.internal.honor_damage == %Damage{}
    end

    test "Spirit of Redemption awards at the initial defeat only", %{character: character} do
      talent = %Holder{spell: %Spell{id: 20_711, attributes: MapSet.new([:passive])}}
      character = %{character | unit: %{character.unit | class: 5, auras: [talent]}}
      {[effect], character} = character |> Entity.take_damage(200, 1000, source: 1) |> honor_effects()
      assert character.unit.health > 0
      {character, history} = receive_damage(character, effect)
      assert history.by_player == %{1 => 200}

      {[effect], character} =
        character |> Entity.take_damage(200, 16_000, source: 2, spell_id: 27_965) |> honor_effects()

      {_character, history} = receive_damage(character, effect)
      assert history.by_player == %{}
    end
  end

  defp receive_damage(character, effect) do
    [resolved] = HonorResolver.resolve(effect)
    Combat.receive_damage(character, resolved)
  end

  defp honor_effects(character) do
    {character, effects} = Effects.drain(character)
    {Enum.filter(effects, &match?(%Effects.HonorDamage{}, &1)), character}
  end

  defp character(_context) do
    character = %Character{
      object: %Object{guid: 2},
      unit: %Unit{race: 2, level: 60, health: 100, max_health: 100, auras: []},
      player: %Player{},
      internal: %Internal{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, spline_nodes: []}
    }

    %{character: character}
  end
end
