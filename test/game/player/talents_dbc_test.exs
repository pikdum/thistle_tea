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
  alias ThistleTea.Game.Player.Talents
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

      assert Enum.map(character.unit.auras, &{&1.spell.id, &1.slot}) == [{rank_five.id, nil}]
      assert ModifierSync.totals(character.unit.auras) == %{{:flat, 5, 10} => -500}
    end
  end

  describe "reset/1" do
    test "forgets shaman two-handed proficiencies while retaining learned skill values for retraining" do
      spells = [16_269, 197, 198, 199]
      skill = %{value: 245, max: 300, range: :level, always_max?: false}
      character = character()

      character = %{
        character
        | id: System.unique_integer([:positive, :monotonic]),
          unit: %{character.unit | class: 7, race: 2},
          player: %{character.player | skills: %{172 => skill, 160 => %{skill | value: 190}, 54 => skill}},
          internal: %{character.internal | spells: spells, spellbook: SpellLoader.build_spellbook(spells)}
      }

      reset = Talents.reset(%{character: character}).character
      assert reset.internal.spells == [198]
      assert Map.keys(reset.player.skills) == [54]
      assert reset.internal.forgotten_skills[172].value == 245
      assert reset.internal.forgotten_skills[160].value == 190
      assert {:ok, restored, _events} = Spells.learn(reset, [16_269, 197, 199])
      assert restored.player.skills[172].value == 245
      assert restored.player.skills[160].value == 190
      assert restored.internal.forgotten_skills == %{}
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
