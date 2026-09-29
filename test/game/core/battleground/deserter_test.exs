defmodule ThistleTea.Game.Core.Battleground.DeserterTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Battleground.AlteracValley
  alias ThistleTea.Game.Core.Battleground.ArathiBasin
  alias ThistleTea.Game.Core.Battleground.Deserter
  alias ThistleTea.Game.Core.Battleground.Effects
  alias ThistleTea.Game.Core.Battleground.Roster
  alias ThistleTea.Game.Core.Battleground.Template
  alias ThistleTea.Game.Core.Battleground.WarsongGulch
  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.WorldRef

  describe "leave/4" do
    test "all battleground rules penalize early departures once and clear resurrection membership" do
      for {rules, map_id} <- [{WarsongGulch, 489}, {ArathiBasin, 529}, {AlteracValley, 30}],
          phase <- [:countdown, :active] do
        match = match(rules, map_id)
        match = %{match | phase: phase, resurrection_queue: MapSet.new([1])}
        result = rules.leave(match, 1, {0.0, 0.0, 0.0, 0.0}, 900)
        assert %Effects.ApplyDeserter{guid: 1} in result.effects
        assert %Effects.PlayerLeft{guid: 1} in result.effects
        assert result.match.players == %{}
        assert result.match.resurrection_queue == MapSet.new()
        assert rules.leave(result.match, 1, {0.0, 0.0, 0.0, 0.0}, 901).effects == []
      end
    end

    test "completed matches, declined invitations, and offline removal do not penalize players" do
      for {rules, map_id} <- [{WarsongGulch, 489}, {ArathiBasin, 529}, {AlteracValley, 30}],
          {phase, status} <- [{:active, :invited}, {:active, :offline}, {{:ended, :alliance}, :inside}] do
        match = match(rules, map_id)
        match = %{match | phase: phase, players: %{1 => %{match.players[1] | status: status}}}
        result = rules.leave(match, 1, {0.0, 0.0, 0.0, 0.0}, 900)
        refute Enum.any?(result.effects, &match?(%Effects.ApplyDeserter{}, &1))
      end
    end

    test "disconnect retains the reservation without a penalty" do
      match = match(WarsongGulch, 489)
      result = WarsongGulch.disconnect(match, 1, {0.0, 0.0, 0.0, 0.0}, 900)
      assert result.match.players[1].status == :offline
      refute Enum.any?(result.effects, &match?(%Effects.ApplyDeserter{}, &1))
    end
  end

  describe "apply/3" do
    test "uses the ordinary negative aura timer without extending repeated delivery" do
      {character, events} = Deserter.apply(character(), spell(), 1_000)
      assert Deserter.active?(character)
      assert events != []
      assert [holder] = character.unit.auras
      assert holder.negative?
      assert holder.expires_at == 901_000
      assert Deserter.apply(character, spell(), 2_000) == {character, []}
      assert Aura.cancel_spell(character, Deserter.spell_id(), 2_000) == {character, []}
      {character, _events} = Aura.expire_due(character, 900_999)
      assert Deserter.active?(character)
      {character, _events} = Aura.expire_due(character, 901_000)
      refute Deserter.active?(character)
    end

    test "death preserves the penalty and its original expiry" do
      {character, _events} = Deserter.apply(character(), spell(), 1_000)
      character = Entity.take_damage(character, 100, 2_000)
      assert character.unit.health == 0
      assert Deserter.active?(character)
      assert [holder] = character.unit.auras
      assert holder.expires_at == 901_000
    end
  end

  defp match(rules, map_id) do
    players = [%{guid: 1, name: "Test", team: :alliance}]
    result = rules.new(WorldRef.instance(map_id, 1), 1, 5, %Template{}, players, 0)
    Roster.enter(result.match, 1, {WorldRef.open(0), {0.0, 0.0, 0.0, 0.0}}).match
  end

  defp character do
    %Character{
      object: %Object{guid: 1},
      unit: %Unit{level: 60, health: 100, max_health: 100},
      player: %Player{},
      internal: %Internal{world: WorldRef.open(0)},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }
  end

  defp spell do
    %Spell{
      id: 26_013,
      duration_ms: 900_000,
      attributes: MapSet.new([:negative, :death_persistent]),
      effects: [%Effect{index: 0, type: :apply_aura, aura: :dummy, base_points: 0}]
    }
  end
end
