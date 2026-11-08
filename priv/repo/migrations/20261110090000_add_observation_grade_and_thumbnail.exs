defmodule Gallformers.Repo.Migrations.AddObservationGradeAndThumbnail do
  @moduledoc """
  An Observation a statement cites keeps its iNaturalist quality grade
  when the statement was made and a thumbnail (matter `87a1`, Add from
  observation): the Fact inspector says "based on iNaturalist observation
  318135694 (Needs ID)" with its photo.
  """
  use Ecto.Migration

  def change do
    alter table(:attribution_observations) do
      add :quality_grade, :string
      add :thumbnail_url, :string
    end
  end
end
