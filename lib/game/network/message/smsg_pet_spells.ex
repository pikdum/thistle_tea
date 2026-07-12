defmodule ThistleTea.Game.Network.Message.SmsgPetSpells do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_PET_SPELLS

  import Bitwise, only: [<<<: 2, |||: 2]

  @act_command 0x07
  @act_reaction 0x06
  @act_disabled 0x81

  defstruct [:pet_guid, :duration, :reaction_state, :command_state, action_bars: [], spells: [], cooldowns: []]

  def for_pet(pet_guid, spells) when is_integer(pet_guid) and is_list(spells) do
    spell_ids = spells |> Enum.map(& &1.spell_id) |> Enum.filter(&(&1 > 0)) |> Enum.take(4)
    spell_buttons = Enum.map(spell_ids, &button(&1, @act_disabled))
    empty_buttons = List.duplicate(button(0, @act_disabled), 4 - length(spell_buttons))

    %__MODULE__{
      pet_guid: pet_guid,
      duration: 0,
      reaction_state: 1,
      command_state: 1,
      action_bars:
        [button(2, @act_command), button(1, @act_command), button(0, @act_command)] ++
          spell_buttons ++
          empty_buttons ++
          [button(2, @act_reaction), button(1, @act_reaction), button(0, @act_reaction)],
      spells: Enum.map(spell_ids, &button(&1, @act_disabled))
    }
  end

  def clear, do: %__MODULE__{pet_guid: 0}

  @impl ServerMessage
  def to_binary(%__MODULE__{pet_guid: 0}), do: <<0::little-size(64)>>

  def to_binary(%__MODULE__{} = msg) do
    action_bars = Enum.take(msg.action_bars ++ List.duplicate(0, 10), 10)

    <<msg.pet_guid::little-size(64), msg.duration || 0::little-size(32), msg.reaction_state || 1::little-size(8),
      msg.command_state || 1::little-size(8), 0::little-size(8), 0::little-size(8)>> <>
      Enum.reduce(action_bars, <<>>, &(&2 <> <<&1::little-size(32)>>)) <>
      <<length(msg.spells)::little-size(8)>> <>
      Enum.reduce(msg.spells, <<>>, &(&2 <> <<&1::little-size(32)>>)) <>
      <<0::little-size(8)>>
  end

  defp button(action, type), do: action ||| type <<< 24
end
