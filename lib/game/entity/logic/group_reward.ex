defmodule ThistleTea.Game.Entity.Logic.GroupReward do
  @moduledoc "Plans creature kill rewards from nearby party members and the original tagger."

  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Experience

  defmodule Member do
    @moduledoc false
    defstruct [:guid, :level, alive?: false, ghost?: false, original_tagger?: false]
  end

  defmodule Award do
    @moduledoc false
    defstruct [:guid, :pet_max_level, xp: 0, pet_xp: 0, quest?: false]
  end

  def plan(members, victim_level, opts \\ []) do
    shares =
      members
      |> Enum.filter(&(&1.alive? or &1.original_tagger?))
      |> Experience.group_rewards(victim_level, opts)
      |> Map.new(&{&1.guid, &1})

    if map_size(shares) == 0 do
      []
    else
      Enum.map(members, &award(&1, shares))
    end
  end

  def for_recipient(%Award{} = award, character) do
    award = if Death.alive?(character), do: award, else: %{award | xp: 0, pet_xp: 0}
    %{award | quest?: award.quest? and not Death.ghost?(character)}
  end

  defp award(%Member{alive?: true, guid: guid, ghost?: ghost?}, shares) do
    share = Map.fetch!(shares, guid)

    %Award{
      guid: guid,
      xp: share.xp,
      pet_xp: share.pet_xp,
      pet_max_level: share.pet_max_level,
      quest?: not ghost?
    }
  end

  defp award(%Member{guid: guid, ghost?: ghost?}, _shares), do: %Award{guid: guid, quest?: not ghost?}
end
