defmodule ThistleTea.Game.Core.Creature.CharmSpells do
  @moduledoc """
  The abilities a creature offers whoever charms or possesses it. Each of its
  four slots lists candidate spells with a percent availability; one roll per
  slot picks at most one when the creature is built, so a spawn keeps the same
  abilities however often it is controlled. A picked spell recovers over the
  slot's cooldown range instead of its own, for the creature's own casts too.

  A creature under someone else's control is commanded through these spells
  alone, never its full combat spellbook; spells that charm or possess are
  never offered. Pets keep their own spellbooks.
  """

  alias ThistleTea.Game.Core.AI.CreatureSpell
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.Internal.Pet
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Rolls
  alias ThistleTea.Game.Core.Spell

  @slot_rolls [
    {0, :charm_slot_0, :charm_cooldown_0},
    {1, :charm_slot_1, :charm_cooldown_1},
    {2, :charm_slot_2, :charm_cooldown_2},
    {3, :charm_slot_3, :charm_cooldown_3}
  ]

  defmodule Option do
    @moduledoc false
    @enforce_keys [:slot, :spell, :availability]
    defstruct [:slot, :spell, :availability, cooldown_min_ms: 0, cooldown_max_ms: 0]
  end

  def select(slots, %Rolls{} = rolls) when is_map(slots) do
    for {slot, availability_roll, cooldown_roll} <- @slot_rolls,
        %Option{} = option <- [pick(Map.get(slots, slot, []), Rolls.uniform(rolls, availability_roll) * 100.0)] do
      cooldown = Rolls.integer(rolls, cooldown_roll, option.cooldown_min_ms, option.cooldown_max_ms)
      %{option.spell | recovery_time_ms: cooldown}
    end
  end

  def pick(options, roll) when is_list(options) and is_number(roll) do
    Enum.reduce_while(options, 0.0, fn %Option{availability: chance} = option, sum ->
      if roll > sum and roll <= sum + chance, do: {:halt, option}, else: {:cont, sum + chance}
    end)
    |> case do
      %Option{} = option -> option
      _sum -> nil
    end
  end

  def attach(%Mob{internal: %Internal{creature: %Creature{} = creature} = internal} = mob, spells)
      when is_list(spells) do
    spellbook = Map.merge(internal.spellbook || %{}, Map.new(spells, &{&1.id, &1}))
    creature = %{creature | charm_spells: Enum.map(spells, & &1.id)}
    %{mob | internal: %{internal | spellbook: spellbook, creature: creature}}
  end

  def controlled?(%Mob{internal: %Internal{pet: %Pet{kind: kind, possession_original_kind: nil}}}),
    do: kind in [:charmed, :possessed]

  def controlled?(%Mob{}), do: false

  def control_spells(%Mob{internal: %Internal{spellbook: spellbook}} = mob) when is_map(spellbook) do
    if controlled?(mob) do
      spellbook |> Map.take(charm_ids(mob)) |> Map.reject(fn {_id, spell} -> controls_others?(spell) end)
    else
      spellbook
    end
  end

  def control_spells(%Mob{}), do: %{}

  def bar_spells(%Mob{} = mob) do
    spells = control_spells(mob)
    order = if controlled?(mob), do: charm_ids(mob), else: spells |> Map.keys() |> Enum.sort()

    order
    |> Enum.map(&Map.get(spells, &1))
    |> Enum.reject(&(is_nil(&1) or Spell.attribute?(&1, :passive)))
  end

  def entries(%Mob{} = mob) do
    Enum.map(bar_spells(mob), fn spell ->
      %CreatureSpell{spell_id: spell.id, cast_target: if(Spell.harmful?(spell), do: :victim, else: :self)}
    end)
  end

  defp charm_ids(%Mob{internal: %Internal{creature: %Creature{charm_spells: ids}}}) when is_list(ids), do: ids
  defp charm_ids(%Mob{}), do: []

  defp controls_others?(%Spell{effects: effects}) when is_list(effects),
    do: Enum.any?(effects, &(&1.aura in [:mod_charm, :mod_possess]))

  defp controls_others?(_spell), do: false
end
