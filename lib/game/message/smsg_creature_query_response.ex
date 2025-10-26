defmodule ThistleTea.Game.Message.SmsgCreatureQueryResponse do
  use ThistleTea.Game.ServerMessage, :SMSG_CREATURE_QUERY_RESPONSE

  defstruct [
    :creature_entry,
    :name1,
    :name2,
    :name3,
    :name4,
    :sub_name,
    :type_flags,
    :creature_type,
    :creature_family,
    :creature_rank,
    :spell_data_id,
    :display_id,
    :civilian,
    :racial_leader,
    :found,
    unknown0: 0
  ]

  @impl ServerMessage
  def to_binary(%__MODULE__{
        creature_entry: creature_entry,
        found: found,
        name1: name1,
        name2: name2,
        name3: name3,
        name4: name4,
        sub_name: sub_name,
        type_flags: type_flags,
        creature_type: creature_type,
        creature_family: creature_family,
        creature_rank: creature_rank,
        unknown0: unknown0,
        spell_data_id: spell_data_id,
        display_id: display_id,
        civilian: civilian,
        racial_leader: racial_leader
      }) do
    entry =
      if found do
        creature_entry
      else
        Bitwise.bor(creature_entry, 0x80000000)
      end

    <<entry::little-size(32)>> <>
      if found do
        (name1 || "") <>
          <<0>> <>
          (name2 || "") <>
          <<0>> <>
          (name3 || "") <>
          <<0>> <>
          (name4 || "") <>
          <<0>> <>
          (sub_name || "") <>
          <<0>> <>
          <<
            type_flags || 0::little-size(32),
            creature_type || 0::little-size(32),
            creature_family || 0::little-size(32),
            creature_rank || 0::little-size(32),
            unknown0 || 0::little-size(32),
            spell_data_id || 0::little-size(32),
            display_id || 0::little-size(32),
            civilian || 0::little-size(8),
            racial_leader || 0::little-size(8)
          >>
      else
        <<>>
      end
  end
end
