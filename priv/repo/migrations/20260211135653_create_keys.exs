defmodule Gallformers.Repo.Migrations.CreateKeys do
  use Gallformers.Migration

  def change do
    create table(:keys) do
      add :slug, :string, null: false
      add :title, :string, null: false
      add :subtitle, :string
      add :authors, :string
      add :citation, :string
      add :citation_url, :string
      add :description, :text
      add :version, :string, null: false
      add :couplets, :text, null: false

      timestamps()
    end

    create unique_index(:keys, [:slug])

    # Seed existing keys from JSON files
    execute(&seed_keys/0, fn -> :ok end)
  end

  defp seed_keys do
    keys_dir = Path.join(:code.priv_dir(:gallformers), "keys")

    keys_dir
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".json"))
    |> Enum.each(fn filename ->
      path = Path.join(keys_dir, filename)
      data = path |> File.read!() |> Jason.decode!()

      now =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.truncate(:second)
        |> NaiveDateTime.to_string()

      repo().query!(
        """
        INSERT INTO keys (slug, title, subtitle, authors, citation, citation_url, description, version, couplets, inserted_at, updated_at)
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)
        """,
        [
          data["slug"],
          data["title"],
          data["subtitle"],
          Jason.encode!(data["authors"] || []),
          data["citation"],
          data["citation_url"],
          data["description"],
          data["version"],
          Jason.encode!(data["couplets"]),
          now,
          now
        ]
      )
    end)
  end
end
