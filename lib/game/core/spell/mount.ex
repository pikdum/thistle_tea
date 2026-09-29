defmodule ThistleTea.Game.Core.Spell.Mount do
  @moduledoc """
  Ground mount cast rules and dismount transitions through the aura owner.
  """
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Area
  alias ThistleTea.Game.Core.Spell.CastContext

  @reindeer_transformation 25_860
  @black_qiraji 26_656
  @ahn_qiraj_temple 531
  @mount_forms [nil, 0, 17, 18, 19, 28, 30]

  defmodule Context do
    @moduledoc "Map, area, transport exterior, and display facts resolved by the world boundary."
    defstruct [:area_id, :outdoors?, mount_allowed?: true, display_mountable?: false]
  end

  def spell?(%Spell{id: @black_qiraji}), do: true
  def spell?(%Spell{effects: effects}), do: Enum.any?(effects, &(&1.aura == :mounted))

  def dismiss_requested?(%{unit: %{mount_display_id: display}}, %Spell{id: @black_qiraji}),
    do: is_integer(display) and display > 0

  def dismiss_requested?(_entity, _spell), do: false

  def cast_failed(entity, spell, :dont_report, now) do
    if dismiss_requested?(entity, spell), do: dismount(entity, now), else: entity
  end

  def cast_failed(entity, _spell, _reason, _now), do: entity

  def prepare_cast(%Character{} = character, %Spell{} = spell, now) do
    if Spell.attribute?(spell, :passive) or Spell.attribute?(spell, :allow_while_mounted) do
      character
    else
      dismount(character, now)
    end
  end

  def prepare_cast(entity, _spell, _now), do: entity

  def dismount(entity, now) do
    {entity, effects} = Aura.remove_aura_types(entity, [:mounted], now)
    Effects.enqueue(entity, effects)
  end

  def reindeer(entity, %CastContext{caster_guid: guid} = context, now) when entity.object.guid == guid do
    if Aura.has_aura?(entity, :mounted) do
      spell_id = if entity.movement_block.run_speed >= 2 * MovementBlock.default_run_speed(), do: 25_859, else: 25_858
      {entity, events} = Aura.remove_aura_types(entity, [:mounted], now)

      trigger =
        Effects.trigger_spell(guid, context.caster_level, guid, spell_id,
          cast_item_guid: context.cast_item_guid,
          hit_context: context
        )

      {entity, events ++ [trigger]}
    else
      {entity, []}
    end
  end

  def reindeer(entity, _context, _now), do: {entity, []}

  def summon_qiraji(entity, %CastContext{} = context, now) do
    {entity, events} = Aura.remove_aura_types(entity, [:mounted], now)

    summon = %Effects.SummonMount{
      allowed_spell_id: 26_655,
      restricted_spell_id: 25_863,
      cast_item_guid: context.cast_item_guid
    }

    {entity, events ++ [summon]}
  end

  def validate(%Character{} = character, %Spell{} = spell, opts) do
    cond do
      not is_nil(character.internal.taxi_flight) -> {:error, :not_on_taxi}
      dismiss_requested?(character, spell) -> {:error, :dont_report}
      spell.id == @reindeer_transformation and not Aura.has_aura?(character, :mounted) -> {:error, :only_mounted}
      underwater_restricted?(character, spell) -> {:error, :only_abovewater}
      spell?(spell) -> validate_mount(character, spell, Keyword.get(opts, :mount_context, %Context{}), opts)
      true -> :ok
    end
  end

  def validate(_entity, _spell, _opts), do: :ok

  defp validate_mount(character, spell, context, opts) do
    cond do
      transport_restricted?(character, spell, context) ->
        {:error, :no_mounts_allowed}

      context.area_id == 35 ->
        {:error, :no_mounts_allowed}

      map_restricted?(character, spell, context, opts) ->
        {:error, :no_mounts_allowed}

      character.unit.shapeshift_form not in @mount_forms ->
        {:error, :not_shapeshift}

      character.unit.display_id != character.unit.native_display_id and not context.display_mountable? ->
        {:error, :not_shapeshift}

      true ->
        :ok
    end
  end

  defp map_restricted?(character, spell, context, opts) do
    not context.mount_allowed? and not Keyword.get(opts, :triggered?, false) and Area.required_area(spell) == 0 and
      not (spell.id == @black_qiraji and character.internal.world.map_id == @ahn_qiraj_temple)
  end

  defp transport_restricted?(%Character{movement_block: %{transport_guid: guid}}, spell, context)
       when is_integer(guid) and guid > 0, do: spell.id == @black_qiraji or context.outdoors? != true

  defp transport_restricted?(_character, _spell, _context), do: false

  defp underwater_restricted?(character, spell) do
    (spell.id == @black_qiraji or (spell.aura_interrupt_flags &&& Aura.interrupt_mask(:under_water)) != 0) and
      MovementBlock.swimming?(character.movement_block)
  end
end
