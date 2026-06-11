defmodule ThistleTea.Game.Network.Message.SmsgTrainerListTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.SmsgTrainerList

  describe "to_binary/1" do
    test "encodes an empty list with the title" do
      binary =
        SmsgTrainerList.to_binary(%SmsgTrainerList{
          guid: 0x42,
          trainer_type: 0,
          spells: [],
          title: "Hi"
        })

      assert binary == <<0x42::little-size(64), 0::little-size(32), 0::little-size(32), "Hi", 0>>
    end

    test "encodes each spell as a 38-byte entry" do
      spell = %SmsgTrainerList.Spell{
        spell_id: 5145,
        state: :green,
        cost: 200,
        req_level: 6,
        req_skill: 0,
        req_skill_value: 0,
        prev_spell_id: 133,
        req_spell_id: nil
      }

      binary =
        SmsgTrainerList.to_binary(%SmsgTrainerList{
          guid: 0x42,
          trainer_type: 0,
          spells: [spell],
          title: ""
        })

      <<_guid::little-size(64), _trainer_type::little-size(32), 1::little-size(32), entry::binary-size(38), 0>> = binary

      assert entry ==
               <<5145::little-size(32), 0, 200::little-size(32), 0::little-size(32), 0::little-size(32), 6,
                 0::little-size(32), 0::little-size(32), 133::little-size(32), 0::little-size(32), 0::little-size(32)>>
    end

    test "encodes spell states as green 0, red 1, gray 2" do
      for {state, value} <- [green: 0, red: 1, gray: 2] do
        binary =
          SmsgTrainerList.to_binary(%SmsgTrainerList{
            guid: 0,
            spells: [%SmsgTrainerList.Spell{spell_id: 1, state: state}],
            title: ""
          })

        assert <<_header::binary-size(16), 1::little-size(32), ^value, _rest::binary>> = binary
      end
    end

    test "falls back to the required spell when there is no previous rank" do
      spell = %SmsgTrainerList.Spell{spell_id: 1, state: :green, prev_spell_id: nil, req_spell_id: 5143}

      binary = SmsgTrainerList.to_binary(%SmsgTrainerList{guid: 0, spells: [spell], title: ""})

      <<_header::binary-size(16), _spell_and_state::binary-size(5), _costs::binary-size(12), _req_level,
        _skills::binary-size(8), prev::little-size(32), req::little-size(32), _rest::binary>> = binary

      assert prev == 5143
      assert req == 0
    end
  end
end
