defmodule ThistleTea.Game.Network.Message.SmsgTrainerList do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_TRAINER_LIST

  defstruct [:guid, trainer_type: 0, spells: [], title: "Hello! Ready for some training?"]

  defmodule Spell do
    @moduledoc false
    defstruct [
      :spell_id,
      :state,
      :prev_spell_id,
      :req_spell_id,
      cost: 0,
      req_level: 0,
      req_skill: 0,
      req_skill_value: 0
    ]
  end

  @states %{green: 0, red: 1, gray: 2}

  @impl ServerMessage
  def to_binary(%__MODULE__{guid: guid, trainer_type: trainer_type, spells: spells, title: title}) do
    <<
      guid::little-size(64),
      trainer_type::little-size(32),
      length(spells)::little-size(32)
    >> <>
      Enum.map_join(spells, &spell_binary/1) <>
      title <> <<0>>
  end

  defp spell_binary(%Spell{} = spell) do
    prev_spell_id = spell.prev_spell_id || spell.req_spell_id || 0
    req_spell_id = if spell.prev_spell_id, do: spell.req_spell_id || 0, else: 0

    <<
      spell.spell_id::little-size(32),
      Map.fetch!(@states, spell.state),
      spell.cost::little-size(32),
      0::little-size(32),
      0::little-size(32),
      spell.req_level,
      spell.req_skill::little-size(32),
      spell.req_skill_value::little-size(32),
      prev_spell_id::little-size(32),
      req_spell_id::little-size(32),
      0::little-size(32)
    >>
  end
end
