defmodule ThistleTea.Game.Entity.Logic.SelfResurrection do
  @moduledoc """
  Captures Soulstone protection before death removes auras and resolves the
  selected self-resurrection spell into restored resources and a cooldown.
  """

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cooldowns
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Modifiers

  @reincarnation 21_169
  @reincarnation_passive 20_608
  @soulstones %{20_707 => 3026, 20_762 => 20_758, 20_763 => 20_759, 20_764 => 20_760, 20_765 => 20_761}

  def reincarnation_spell_id, do: @reincarnation

  def candidate_spell_id(%{player: %{self_res_spell: id}}) when is_integer(id) and id > 0, do: id

  def candidate_spell_id(entity) do
    if authorized?(entity, @reincarnation), do: @reincarnation, else: 0
  end

  def capture(%{player: player, unit: %{auras: holders}} = entity, now) do
    spell_id =
      if Enum.any?(holders || [], &match?(%Holder{spell: %Spell{id: 27_827}}, &1)) do
        player.self_res_spell || 0
      else
        Enum.find_value(holders || [], 0, &soulstone_spell_id(&1, now))
      end

    %{entity | player: %{player | self_res_spell: spell_id}}
  end

  def capture(entity, _now), do: entity

  defp soulstone_spell_id(%Holder{spell: %Spell{id: id}} = holder, now) do
    if Holder.alive?(holder, now), do: Map.get(@soulstones, id)
  end

  def available?(entity, %Spell{id: id} = spell, now) do
    authorized?(entity, id) and not Cooldowns.on_cooldown?(entity, spell, now) and
      Enum.any?(spell.effects, &match?(%Effect{type: :self_resurrect}, &1))
  end

  def available?(_entity, _spell, _now), do: false

  def resurrect(entity, %Spell{} = spell, now) do
    with true <- Core.dead?(entity) and not Death.ghost?(entity),
         true <- entity.player.self_res_spell == spell.id and available?(entity, spell, now),
         %Effect{} = effect <- Enum.find(spell.effects, &(&1.type == :self_resurrect)) do
      amount = Effect.roll(effect, Spell.level_units(spell, entity.unit.level || 1))
      amount = entity |> Modifiers.value(spell, :all_effects, amount) |> round()
      {health, mana} = restored_resources(entity, effect, amount)
      entity = Cooldowns.start(entity, spell, now)
      {entity, events} = Death.resurrect_with(entity, max(health, 1), mana, now)
      entity = %{entity | unit: %{entity.unit | power4: entity.unit.max_power4 || 0}}
      {:ok, entity, events}
    else
      _unavailable -> {:error, :unavailable}
    end
  end

  defp authorized?(%{internal: %{spellbook: spells}}, @reincarnation) when is_map(spells),
    do: Map.has_key?(spells, @reincarnation_passive)

  defp authorized?(%{player: %{self_res_spell: id}}, id), do: id in [3026, 20_758, 20_759, 20_760, 20_761]
  defp authorized?(_entity, _id), do: false

  defp restored_resources(_entity, %Effect{misc_value: mana}, amount) when amount < 0, do: {-amount, max(mana || 0, 0)}

  defp restored_resources(%{unit: unit}, _effect, amount),
    do: {div((unit.max_health || 0) * amount, 100), div((unit.max_power1 || 0) * amount, 100)}
end
