defmodule ThistleTea.Game.Entity.Logic.DruidTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Druid
  alias ThistleTea.Game.Spell

  describe "consume_swiftmend_hot/3" do
    test "consumes the shortest eligible HoT and converts its remaining spell into healing" do
      rejuvenation = hot(774, 0x10, 100, 8_000)
      regrowth = hot(8936, 0x40, 80, 12_000)
      entity = %Character{unit: %Unit{auras: [regrowth, rejuvenation]}, internal: %Internal{}}
      swiftmend = %Spell{spell_family: 7, family_flags_1: 0x2}

      {entity, healing, _events} = Druid.consume_swiftmend_hot(entity, swiftmend, 1_000)

      assert healing == 400
      assert Enum.map(entity.unit.auras, & &1.spell.id) == [8936]
    end
  end

  defp hot(id, family_flags, amount, expires_at) do
    %Holder{
      spell: %Spell{id: id, spell_family: 7, family_flags_0: family_flags},
      caster_guid: 1,
      slot: rem(id, 32),
      expires_at: expires_at,
      auras: [%Aura{type: :periodic_heal, amount: amount}]
    }
  end
end
