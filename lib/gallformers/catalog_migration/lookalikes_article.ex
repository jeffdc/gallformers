defmodule Gallformers.CatalogMigration.LookalikesArticle do
  @moduledoc """
  The gall-lookalikes Article (`803b` §4, Task 12): the page the old
  `/gall/:id` URLs of the excluded non-galls redirect to
  (`Gallformers.CatalogMigration.NonGalls`). A short placeholder,
  published, created only when no Article has its slug; the curators
  write the real text, which later runs keep.
  """

  alias Gallformers.Articles
  alias Gallformers.CatalogMigration.Report

  @slug "gall-lookalikes"

  @content """
  This page will list organisms that look like galls but are not. Some of \
  them used to have pages of their own on Gallformers.

  The Gallformers curators are writing it.
  """

  @doc "Creates the placeholder Article when missing, counting it in the report."
  @spec run(Report.t()) :: Report.t()
  def run(report) do
    created =
      case Articles.get_article_by_slug(@slug) do
        nil ->
          {:ok, _article} = Articles.create_article(attrs())
          1

        _article ->
          0
      end

    Report.count(report, "gall-lookalikes Article created", created)
  end

  defp attrs do
    %{
      slug: @slug,
      title: "Gall Lookalikes",
      author: "Gallformers Contributors",
      description: "Organisms that look like galls but are not.",
      content: @content,
      tags: ["identification"],
      is_published: true
    }
  end
end
