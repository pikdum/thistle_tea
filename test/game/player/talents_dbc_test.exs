defmodule ThistleTea.Game.Player.TalentsDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura.ModifierSync
  alias ThistleTea.Game.Player.Spells
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.Talent, as: TalentLoader
  alias ThistleTea.Game.WorldRef

  @moduletag :dbc_db

  setup_all do
    :ok = TalentLoader.load_all()
  end

  describe "apply_passives/2" do
    test "replaces lower talent ranks instead of stacking their modifiers" do
      rank_one = SpellLoader.load(11_070)
      rank_five = SpellLoader.load(16_766)

      character =
        %{character() | internal: %Internal{spellbook: %{rank_one.id => rank_one}}}
        |> Spells.apply_passives(1_000)

      character =
        %{character | internal: %{character.internal | spellbook: %{rank_five.id => rank_five}}}
        |> Spells.apply_passives(2_000)

      assert Enum.map(character.unit.auras, & &1.spell.id) == [rank_five.id]
      assert ModifierSync.totals(character.unit.auras) == %{{:flat, 5, 10} => -500}
    end
  end

  defp character do
    %Character{
      object: %Object{guid: 1},
      unit: %Unit{level: 60, health: 100, max_health: 100, auras: []},
      player: %Player{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: %WorldRef{map_id: 0}}
    }
  end
end
