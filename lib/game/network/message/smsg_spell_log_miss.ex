defmodule ThistleTea.Game.Network.Message.SmsgSpellLogMiss do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_SPELLLOGMISS

  @miss_info %{
    miss: 1,
    resist: 2,
    dodge: 3,
    parry: 4,
    block: 5,
    evade: 6,
    immune: 7
  }

  defstruct [:spell_id, :caster, targets: []]

  def miss_info(reason) when is_atom(reason), do: Map.get(@miss_info, reason, 1)
  def miss_info(reason) when is_integer(reason), do: reason

  @impl ServerMessage
  def to_binary(%__MODULE__{spell_id: spell_id, caster: caster, targets: targets}) do
    <<spell_id::little-size(32), caster::little-size(64), 0::little-size(8), length(targets)::little-size(32)>> <>
      Enum.map_join(targets, fn {target_guid, reason} ->
        <<target_guid::little-size(64), miss_info(reason)::little-size(8)>>
      end)
  end
end
