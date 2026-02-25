defmodule Gallformers.Repo.Migrations.CreateAnalyticsSummaryTables do
  use Gallformers.Migration

  def change do
    create table(:daily_stats) do
      add :date, :date, null: false
      add :page_views, :integer, null: false, default: 0
      add :unique_visitors, :integer, null: false, default: 0
    end

    create unique_index(:daily_stats, [:date])

    create table(:daily_page_stats) do
      add :date, :date, null: false
      add :path, :string, null: false
      add :page_views, :integer, null: false, default: 0
      add :unique_visitors, :integer, null: false, default: 0
    end

    create unique_index(:daily_page_stats, [:date, :path])
    create index(:daily_page_stats, [:date])

    create table(:daily_referrer_stats) do
      add :date, :date, null: false
      add :referrer_host, :string
      add :page_views, :integer, null: false, default: 0
    end

    create unique_index(:daily_referrer_stats, [:date, :referrer_host])
    create index(:daily_referrer_stats, [:date])

    create table(:daily_device_stats) do
      add :date, :date, null: false
      add :device_type, :string
      add :count, :integer, null: false, default: 0
    end

    create unique_index(:daily_device_stats, [:date, :device_type])
    create index(:daily_device_stats, [:date])

    create table(:daily_browser_stats) do
      add :date, :date, null: false
      add :browser, :string
      add :count, :integer, null: false, default: 0
    end

    create unique_index(:daily_browser_stats, [:date, :browser])
    create index(:daily_browser_stats, [:date])
  end
end
