defmodule ThistleTea.Game.OutdoorPvp.CapturePoint.TemplateTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate
  alias ThistleTea.Game.OutdoorPvp.CapturePoint.Template

  describe "from_game_object/1" do
    @tag :vmangos_db
    test "loads all four capture points with the reference timings and slider fields" do
      rows = Mangos.Repo.all(from(template in Mangos.GameObjectTemplate, where: template.type == 29))
      assert length(rows) == 4

      for row <- rows do
        template = row |> GameObjectTemplate.build() |> Template.from_game_object()
        assert template.radius == 80
        assert template.neutral_percent == 20
        assert template.min_time == 480
        assert template.max_time == 1200
        assert {template.display_state, template.position_state, template.neutral_state} == {2426, 2427, 2428}
      end
    end

    test "ignores non-capture objects and invalid timing or radius data" do
      assert Template.from_game_object(%GameObjectTemplate{type: 10}) == nil
      assert Template.from_game_object(%GameObjectTemplate{type: 29, data: []}) == nil
    end
  end
end
