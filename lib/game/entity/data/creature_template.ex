defmodule ThistleTea.Game.Entity.Data.CreatureTemplate do
  @moduledoc false
  alias ThistleTea.DB.Mangos

  defstruct [
    :entry,
    :name,
    :sub_name,
    :type_flags,
    :creature_type,
    :family,
    :rank,
    :display_id,
    :civilian,
    :racial_leader
  ]

  def build(%Mangos.CreatureTemplate{} = ct) do
    %__MODULE__{
      entry: ct.entry,
      name: ct.name,
      sub_name: ct.sub_name,
      type_flags: ct.creature_type_flags,
      creature_type: ct.creature_type,
      family: ct.family,
      rank: ct.rank,
      display_id: ct.model_id1,
      civilian: ct.civilian,
      racial_leader: ct.racial_leader
    }
  end
end
