defmodule ThistleTea.Game.Network.Message.SmsgPetSpells do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_PET_SPELLS

  import Bitwise, only: [<<<: 2, |||: 2]

  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Spell

  @act_command 0x07
  @act_reaction 0x06
  @act_enabled 0xC1
  @act_disabled 0x81
  @act_passive 0x01

  defstruct [:pet_guid, :duration, :reaction_state, :command_state, action_bars: [], spells: [], cooldowns: []]

  def for_pet(pet_guid, spells) when is_integer(pet_guid) and is_list(spells) do
    for_pet(pet_guid, spells, MapSet.new())
  end

  def for_pet(pet_guid, spells, %MapSet{} = autocast) when is_integer(pet_guid) and is_list(spells) do
    spells = spells |> Enum.filter(&(spell_id(&1) > 0)) |> Enum.sort_by(&spell_id/1)
    spell_ids = spells |> Enum.reject(&passive?/1) |> Enum.map(&spell_id/1) |> Enum.take(4)
    spell_buttons = Enum.map(spell_ids, &button(&1, spell_state(&1, autocast)))
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
      spells:
        Enum.map(
          spells,
          &button(spell_id(&1), if(passive?(&1), do: @act_passive, else: spell_state(spell_id(&1), autocast)))
        )
    }
  end

  def for_pet(pet_guid, spells, %Pet{} = control) do
    packet = for_pet(pet_guid, spells, control.autocast)

    action_bars =
      Enum.with_index(packet.action_bars, fn default, slot ->
        case Map.get(control.action_bar, slot) do
          {id, type} -> button(id, type)
          _ -> default
        end
      end)

    %{
      packet
      | action_bars: action_bars,
        reaction_state: reaction_code(control.reaction_state),
        command_state: command_code(control.command_state)
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

  defp spell_state(spell_id, autocast) do
    if MapSet.member?(autocast, spell_id), do: @act_enabled, else: @act_disabled
  end

  defp passive?(%Spell{} = spell), do: Spell.attribute?(spell, :passive)
  defp passive?(_spell), do: false

  defp reaction_code(:passive), do: 0
  defp reaction_code(:defensive), do: 1
  defp reaction_code(:aggressive), do: 2

  defp command_code(:stay), do: 0
  defp command_code(:follow), do: 1
  defp command_code(:attack), do: 2

  defp spell_id(%{spell_id: spell_id}) when is_integer(spell_id), do: spell_id
  defp spell_id(%{id: spell_id}) when is_integer(spell_id), do: spell_id
  defp spell_id(spell_id) when is_integer(spell_id), do: spell_id
  defp spell_id(_spell), do: 0
end
