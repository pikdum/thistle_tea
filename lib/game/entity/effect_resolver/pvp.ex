defmodule ThistleTea.Game.Entity.EffectResolver.Pvp do
  @moduledoc """
  Resolves combat participants to their controlling players and snapshots the
  PvP facts needed by each owner. No other player's state is written here.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Pvp, as: PvpLogic
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.Metadata

  @fields [:owner_guid, :pvp?, :pvp_combat?, :unit_flags, :free_for_all?, :contested_pvp?, :in_combat]

  def spell_contacts(entity, source, target, %Spell{} = spell, outcome, opts \\ []) do
    case spell_contact(spell, outcome) do
      {role, combat?, only_in_combat?} ->
        opts = Keyword.merge(opts, combat?: combat?, only_in_combat?: only_in_combat?)
        contacts(entity, source, target, role, opts)

      nil ->
        []
    end
  end

  defp spell_contact(spell, outcome) do
    cond do
      Spell.harmful?(spell) -> hostile_spell_contact(spell, outcome)
      outcome != :hit -> nil
      friendly_target?(spell) -> {:assist, assistance_combat?(spell), false}
      assistance_combat?(spell) -> {:assist, true, true}
      true -> nil
    end
  end

  defp hostile_spell_contact(spell, outcome) do
    cond do
      Spell.starts_combat?(spell, outcome) and not Spell.attribute?(spell, :no_initial_threat) ->
        {:attack, true, false}

      Spell.attribute?(spell, :pvp_enabling) or (outcome == :miss and not peaceful_only?(spell)) ->
        {:attack, false, false}

      true ->
        nil
    end
  end

  defp peaceful_only?(spell) do
    Spell.attribute?(spell, :not_in_combat) and Spell.attribute?(spell, :only_peaceful_targets)
  end

  defp assistance_combat?(spell) do
    not Spell.attribute?(spell, :no_threat) and not Spell.attribute?(spell, :no_initial_threat)
  end

  defp friendly_target?(%Spell{effects: effects}) do
    friendly_targets = [
      :target_ally,
      :chain_heal,
      :pet,
      :party_member,
      :party_around_caster,
      :party_around_target,
      :raid_and_class
    ]

    Enum.any?(effects, fn effect ->
      effect.implicit_target_a in friendly_targets or effect.implicit_target_b in friendly_targets
    end)
  end

  def contacts(entity, source, target, role, opts \\ []) do
    get_metadata = Keyword.get(opts, :metadata, &Metadata.query(&1, @fields))
    now = Keyword.get_lazy(opts, :now, &Time.now/0)
    source = profile(source, entity, get_metadata)
    target = profile(target, entity, get_metadata)
    effects = contact(source.player_guid, role, target, now, opts)

    if role == :attack do
      source = %{source | pvp?: source.pvp? or (is_integer(source.player_guid) and target.pvp?)}
      effects ++ contact(target.player_guid, :attacked, source, now, opts)
    else
      effects
    end
  end

  defp contact(player, role, %{pvp?: true, player_guid: other_player} = other, now, opts)
       when is_integer(player) and player != other_player do
    if Keyword.get(opts, :only_in_combat?, false) and not other.in_combat do
      []
    else
      [
        %Effects.PvpContact{
          target_guid: player,
          role: role,
          other: other,
          now: now,
          combat?: Keyword.get(opts, :combat?, true)
        }
      ]
    end
  end

  defp contact(_player, _role, _other, _now, _opts), do: []

  defp profile(guid, %Character{object: %{guid: guid}, internal: %{possession: nil}} = entity, _get_metadata) do
    %{
      player_guid: guid,
      pvp?: PvpLogic.active?(entity),
      pvp_combat?: PvpLogic.combat?(entity),
      free_for_all?: PvpLogic.free_for_all?(entity),
      contested_pvp?: PvpLogic.contested?(entity),
      in_combat: entity.internal.in_combat == true
    }
  end

  defp profile(guid, _entity, get_metadata) do
    metadata = if is_integer(guid), do: get_metadata.(guid) || %{}, else: %{}
    player = controlling_player(guid, metadata)
    owner = if is_integer(player) and player != guid, do: get_metadata.(player) || %{}, else: metadata

    %{
      player_guid: player,
      pvp?: Map.get(owner, :pvp?) == true or PvpLogic.active?(owner),
      pvp_combat?: Map.get(owner, :pvp_combat?) == true,
      free_for_all?: Map.get(owner, :free_for_all?) == true,
      contested_pvp?: Map.get(owner, :contested_pvp?) == true,
      in_combat: Map.get(owner, :in_combat) == true or Map.get(metadata, :in_combat) == true
    }
  end

  defp controlling_player(guid, metadata) do
    cond do
      player_guid?(Map.get(metadata, :owner_guid)) -> metadata.owner_guid
      player_guid?(guid) -> guid
      true -> nil
    end
  end

  defp player_guid?(guid) when is_integer(guid) and guid > 0, do: Guid.entity_type(guid) == :player
  defp player_guid?(_guid), do: false
end
