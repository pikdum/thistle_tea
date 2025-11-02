defmodule ThistleTea.Game.Network.Message.SmsgInitialSpells do
  use ThistleTea.Game.Network.ServerMessage, :SMSG_INITIAL_SPELLS

  defmodule InitialSpell do
    defstruct [:spell_id, :unknown1]
  end

  defmodule CooldownSpell do
    defstruct [:spell_id, :item_id, :spell_category, :cooldown, :category_cooldown]
  end

  defstruct [
    :unknown1,
    :initial_spells,
    :cooldowns
  ]

  @impl ServerMessage
  def to_binary(%__MODULE__{unknown1: unknown1, initial_spells: initial_spells, cooldowns: cooldowns}) do
    spell_count = length(initial_spells)
    cooldown_count = length(cooldowns)

    spells_binary =
      initial_spells
      |> Enum.map(fn %InitialSpell{spell_id: spell_id, unknown1: u1} ->
        <<spell_id::little-size(16), u1::little-size(16)>>
      end)
      |> Enum.reduce(<<>>, fn x, acc -> acc <> x end)

    cooldowns_binary =
      cooldowns
      |> Enum.map(fn %CooldownSpell{
                       spell_id: spell_id,
                       item_id: item_id,
                       spell_category: spell_category,
                       cooldown: cooldown,
                       category_cooldown: category_cooldown
                     } ->
        <<spell_id::little-size(16), item_id::little-size(16), spell_category::little-size(16),
          cooldown::little-size(32), category_cooldown::little-size(32)>>
      end)
      |> Enum.reduce(<<>>, fn x, acc -> acc <> x end)

    <<unknown1::little-size(8), spell_count::little-size(16)>> <>
      spells_binary <> <<cooldown_count::little-size(16)>> <> cooldowns_binary
  end
end
