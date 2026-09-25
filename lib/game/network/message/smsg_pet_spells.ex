defmodule ThistleTea.Game.Network.Message.SmsgPetSpells do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_PET_SPELLS

  import Bitwise, only: [<<<: 2, |||: 2]

  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Logic.PetControls
  alias ThistleTea.Game.Spell

  @act_command 0x07
  @act_passive 0x01

  defstruct [:pet_guid, :duration, :reaction_state, :command_state, action_bars: [], spells: [], cooldowns: []]

  def for_pet(pet_guid, spells) when is_integer(pet_guid) and is_list(spells) do
    for_pet(pet_guid, spells, MapSet.new())
  end

  def for_pet(pet_guid, spells, %MapSet{} = autocast) do
    for_pet(pet_guid, spells, %Pet{autocast: autocast})
  end

  def for_pet(pet_guid, spells, %Pet{} = control) do
    spellbook =
      spells
      |> Enum.filter(&(spell_id(&1) > 0))
      |> Map.new(fn
        %Spell{} = spell -> {spell.id, spell}
        entry -> {spell_id(entry), %Spell{id: spell_id(entry)}}
      end)

    control = PetControls.normalize(control, spellbook)

    %__MODULE__{
      pet_guid: pet_guid,
      duration: 0,
      reaction_state: reaction_code(control.reaction_state),
      command_state: command_code(control.command_state),
      action_bars:
        Enum.map(0..9, fn slot ->
          {id, type} = Map.fetch!(control.action_bar, slot)
          button(id, type)
        end),
      spells:
        spellbook
        |> Map.values()
        |> Enum.sort_by(& &1.id)
        |> Enum.map(fn spell ->
          button(spell.id, PetControls.spell_state(spell, control.autocast))
        end)
    }
  end

  def for_possession(guid, spells, duration \\ 0) do
    buttons = spells |> Enum.reject(&passive?/1) |> Enum.take(9) |> Enum.map(&button(spell_id(&1), @act_passive))

    %__MODULE__{
      pet_guid: guid,
      duration: duration,
      reaction_state: 0,
      command_state: 0,
      action_bars: [button(2, @act_command)] ++ buttons ++ List.duplicate(button(0, @act_passive), 9 - length(buttons))
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
