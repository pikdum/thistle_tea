defmodule ThistleTea.Game.Spell.ProcRule do
  @moduledoc """
  Runtime proc restrictions loaded from VMangos `spell_proc_event`.
  """

  defstruct school_mask: 0,
            spell_family: 0,
            family_mask_0: 0,
            family_mask_1: 0,
            proc_flags: 0,
            proc_ex: 0,
            ppm_rate: 0.0,
            custom_chance: 0.0,
            cooldown_ms: 0
end
