defmodule ThistleTea.Test.FactionFixtures do
  @moduledoc """
  Seeds `Loader.Faction` with copies of the DBC faction templates that
  entity-server tests publish, so presence and mob metadata never fall
  through to `db/dbc.sqlite`. Use from synchronous modules as
  `setup [{FactionFixtures, :seed}, ...]`.
  """
  import ExUnit.Callbacks, only: [on_exit: 1]

  alias ThistleTea.Game.Core.Combat.FactionTemplate
  alias ThistleTea.Game.World.Loader.Faction

  @templates [
    %FactionTemplate{id: 1, faction: 1, flags: 72, faction_group: 3, friend_group: 2, enemy_group: 12},
    %FactionTemplate{id: 14, faction: 14, faction_group: 8, enemy_group: 1},
    %FactionTemplate{id: 35, faction: 31, friend_group: 1, friends_0: 31}
  ]

  def seed(_context) do
    ids = Enum.map(@templates, & &1.id)
    previous = Enum.flat_map(ids, &:ets.lookup(Faction, &1))

    :ets.insert(
      Faction,
      for(
        template <- @templates,
        do:
          {template.id,
           %{faction_template_id: template.id, faction_template: template, faction_can_have_reputation?: false}}
      )
    )

    on_exit(fn ->
      Enum.each(ids, &:ets.delete(Faction, &1))
      :ets.insert(Faction, previous)
    end)
  end
end
