defmodule ThistleTea.Game.Entity.Logic.Effects.MovementTypes do
  @moduledoc false

  effects = [
    {:Charge, [:target_guid], []},
    {:MovementStopped, [], []},
    {:MovementSpeedChanged, [:speed], []},
    {:MovementRootChanged, [:rooted?], []},
    {:FeatherFallChanged, [:enabled?], []},
    {:HoverChanged, [:enabled?], []},
    {:WaterWalkChanged, [:enabled?], []},
    {:MonsterMove, [:move_opts], []},
    {:Teleport, [:position], []},
    {:Leap, [:position], []},
    {:TeleportToSpellTarget, [:spell_id], []},
    {:SetFacing, [:facing], []}
  ]

  for {name, required, optional} <- effects do
    type = name |> Atom.to_string() |> Macro.underscore() |> String.to_atom()

    defmodule Module.concat(ThistleTea.Game.Entity.Logic.Effects, name) do
      @moduledoc false
      @enforce_keys required
      defstruct [type: type] ++ required ++ optional
    end
  end
end
