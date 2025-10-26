defmodule ThistleTea.Game.Message.SmsgGameobjectQueryResponse do
  use ThistleTea.Game.ServerMessage, :SMSG_GAMEOBJECT_QUERY_RESPONSE

  defstruct [
    :entry_id,
    :info_type,
    :display_id,
    :name1,
    :name2,
    :name3,
    :name4,
    :name5,
    :raw_data
  ]

  @impl ServerMessage
  def to_binary(%__MODULE__{entry_id: entry_id, info_type: nil}) do
    import Bitwise

    <<entry_id ||| 0x80000000::little-size(32)>>
  end

  def to_binary(%__MODULE__{
        entry_id: entry_id,
        info_type: info_type,
        display_id: display_id,
        name1: name1,
        name2: name2,
        name3: name3,
        name4: name4,
        name5: name5,
        raw_data: raw_data
      }) do
    raw_data_binary =
      raw_data
      |> Enum.reduce(<<>>, fn x, acc -> acc <> <<x::little-size(32)>> end)

    <<entry_id::little-size(32), info_type::little-size(32), display_id::little-size(32)>> <>
      name1 <>
      <<0>> <>
      name2 <>
      <<0>> <>
      name3 <>
      <<0>> <>
      name4 <>
      <<0>> <>
      name5 <>
      <<0>> <>
      raw_data_binary
  end
end
