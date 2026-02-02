defmodule GallformersWeb.Schemas do
  @moduledoc """
  OpenAPI schemas for the Gallformers API.
  """

  alias OpenApiSpex.Schema

  defmodule Error do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Error",
      type: :object,
      properties: %{
        error: %Schema{type: :string, description: "Error message"}
      },
      required: [:error],
      example: %{error: "Resource not found"}
    })
  end

  defmodule Alias do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Alias",
      description: "An alternative name for a species",
      type: :object,
      properties: %{
        id: %Schema{type: :integer},
        name: %Schema{type: :string},
        type: %Schema{type: :string},
        description: %Schema{type: :string, nullable: true}
      },
      required: [:id, :name],
      example: %{id: 1, name: "Common Oak Gall", type: "common", description: nil}
    })
  end

  defmodule Host do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Host",
      description: "A host plant for a gall",
      type: :object,
      properties: %{
        id: %Schema{type: :integer},
        name: %Schema{type: :string}
      },
      required: [:id, :name],
      example: %{id: 42, name: "Quercus alba"}
    })
  end

  defmodule FilterField do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "FilterField",
      description: "A filter field value (color, shape, texture, etc.)",
      type: :object,
      properties: %{
        id: %Schema{type: :integer},
        field: %Schema{type: :string},
        description: %Schema{type: :string, nullable: true}
      },
      required: [:id, :field],
      example: %{id: 1, field: "green", description: nil}
    })
  end

  defmodule Gall do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Gall",
      description: "A gall-forming species",
      type: :object,
      properties: %{
        id: %Schema{type: :integer},
        name: %Schema{type: :string},
        gall_id: %Schema{type: :integer},
        datacomplete: %Schema{type: :boolean},
        abundance_id: %Schema{type: :integer, nullable: true},
        abundance: %Schema{type: :string, nullable: true},
        detachable: %Schema{
          type: :string,
          enum: ["unknown", "integral", "detachable", "both"],
          nullable: true
        },
        undescribed: %Schema{type: :boolean},
        aliases: %Schema{type: :array, items: GallformersWeb.Schemas.Alias},
        hosts: %Schema{type: :array, items: GallformersWeb.Schemas.Host},
        colors: %Schema{type: :array, items: GallformersWeb.Schemas.FilterField},
        shapes: %Schema{type: :array, items: GallformersWeb.Schemas.FilterField},
        textures: %Schema{type: :array, items: GallformersWeb.Schemas.FilterField},
        plant_parts: %Schema{type: :array, items: GallformersWeb.Schemas.FilterField},
        alignments: %Schema{type: :array, items: GallformersWeb.Schemas.FilterField},
        walls: %Schema{type: :array, items: GallformersWeb.Schemas.FilterField},
        cells: %Schema{type: :array, items: GallformersWeb.Schemas.FilterField},
        seasons: %Schema{type: :array, items: GallformersWeb.Schemas.FilterField},
        forms: %Schema{type: :array, items: GallformersWeb.Schemas.FilterField},
        places: %Schema{type: :array, items: %Schema{type: :string}},
        excludedPlaces: %Schema{type: :array, items: %Schema{type: :string}}
      },
      required: [:id, :name, :gall_id, :undescribed]
    })
  end

  defmodule GallListResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "GallListResponse",
      description: "Paginated list of galls",
      type: :object,
      properties: %{
        data: %Schema{type: :array, items: GallformersWeb.Schemas.Gall},
        total: %Schema{type: :integer},
        limit: %Schema{type: :integer, nullable: true},
        offset: %Schema{type: :integer}
      },
      required: [:data, :total, :offset]
    })
  end

  defmodule RandomGall do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "RandomGall",
      description: "A random gall with image for the home page",
      type: :object,
      properties: %{
        id: %Schema{type: :integer},
        name: %Schema{type: :string},
        undescribed: %Schema{type: :boolean},
        image_path: %Schema{type: :string},
        image_url: %Schema{type: :string},
        image_creator: %Schema{type: :string, nullable: true},
        image_license: %Schema{type: :string, nullable: true}
      },
      required: [:id, :name, :undescribed, :image_url]
    })
  end

  defmodule IDGall do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "IDGall",
      description: "Gall optimized for the ID tool with filter fields as strings",
      type: :object,
      properties: %{
        id: %Schema{type: :integer},
        name: %Schema{type: :string},
        undescribed: %Schema{type: :boolean},
        detachable: %Schema{
          type: :string,
          enum: ["unknown", "integral", "detachable", "both"]
        },
        alignments: %Schema{type: :array, items: %Schema{type: :string}},
        cells: %Schema{type: :array, items: %Schema{type: :string}},
        colors: %Schema{type: :array, items: %Schema{type: :string}},
        forms: %Schema{type: :array, items: %Schema{type: :string}},
        plant_parts: %Schema{type: :array, items: %Schema{type: :string}},
        seasons: %Schema{type: :array, items: %Schema{type: :string}},
        shapes: %Schema{type: :array, items: %Schema{type: :string}},
        textures: %Schema{type: :array, items: %Schema{type: :string}},
        walls: %Schema{type: :array, items: %Schema{type: :string}},
        places: %Schema{type: :array, items: %Schema{type: :string}},
        family: %Schema{type: :string},
        genus: %Schema{type: :string},
        hosts: %Schema{type: :array, items: GallformersWeb.Schemas.Host},
        imageUrl: %Schema{type: :string, nullable: true}
      },
      required: [:id, :name, :undescribed]
    })
  end

  defmodule Image do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Image",
      description: "An image for a species",
      type: :object,
      properties: %{
        id: %Schema{type: :integer},
        path: %Schema{type: :string},
        url: %Schema{type: :string},
        default: %Schema{type: :boolean},
        creator: %Schema{type: :string, nullable: true},
        attribution: %Schema{type: :string, nullable: true},
        sourcelink: %Schema{type: :string, nullable: true},
        license: %Schema{type: :string, nullable: true},
        licenselink: %Schema{type: :string, nullable: true},
        caption: %Schema{type: :string, nullable: true}
      },
      required: [:id, :path, :url]
    })
  end

  defmodule RelatedGall do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "RelatedGall",
      description: "A related gall (same binomial name)",
      type: :object,
      properties: %{
        id: %Schema{type: :integer},
        name: %Schema{type: :string}
      },
      required: [:id, :name]
    })
  end

  defmodule HostResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "HostResponse",
      description: "A host plant species",
      type: :object,
      properties: %{
        id: %Schema{type: :integer},
        name: %Schema{type: :string},
        taxoncode: %Schema{type: :string},
        datacomplete: %Schema{type: :boolean},
        places: %Schema{type: :array, items: %Schema{type: :string}},
        galls: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              id: %Schema{type: :integer},
              name: %Schema{type: :string},
              undescribed: %Schema{type: :boolean}
            }
          }
        }
      },
      required: [:id, :name]
    })
  end

  defmodule HostListResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "HostListResponse",
      description: "Paginated list of hosts",
      type: :object,
      properties: %{
        data: %Schema{type: :array, items: GallformersWeb.Schemas.HostResponse},
        total: %Schema{type: :integer},
        limit: %Schema{type: :integer, nullable: true},
        offset: %Schema{type: :integer}
      },
      required: [:data, :total, :offset]
    })
  end

  defmodule Taxonomy do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Taxonomy",
      description: "A taxonomy entry (family, genus, or section)",
      type: :object,
      properties: %{
        id: %Schema{type: :integer},
        name: %Schema{type: :string},
        type: %Schema{type: :string, enum: ["family", "genus", "section"]},
        description: %Schema{type: :string, nullable: true},
        parent_id: %Schema{type: :integer, nullable: true}
      },
      required: [:id, :name, :type]
    })
  end

  defmodule Source do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Source",
      description: "A scientific reference/citation",
      type: :object,
      properties: %{
        id: %Schema{type: :integer},
        title: %Schema{type: :string},
        author: %Schema{type: :string, nullable: true},
        pubyear: %Schema{type: :string, nullable: true},
        link: %Schema{type: :string, nullable: true},
        citation: %Schema{type: :string, nullable: true},
        datacomplete: %Schema{type: :boolean}
      },
      required: [:id, :title]
    })
  end

  defmodule Glossary do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Glossary",
      description: "A glossary term and definition",
      type: :object,
      properties: %{
        id: %Schema{type: :integer},
        word: %Schema{type: :string},
        definition: %Schema{type: :string},
        urls: %Schema{type: :string, nullable: true}
      },
      required: [:id, :word, :definition]
    })
  end

  defmodule Place do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Place",
      description: "A geographic place (state, province, etc.)",
      type: :object,
      properties: %{
        id: %Schema{type: :integer},
        name: %Schema{type: :string},
        code: %Schema{type: :string},
        type: %Schema{type: :string},
        parent_id: %Schema{type: :integer, nullable: true}
      },
      required: [:id, :name, :code, :type]
    })
  end

  defmodule SearchResults do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "SearchResults",
      description: "Global search results grouped by type",
      type: :object,
      properties: %{
        galls: %Schema{type: :array, items: %Schema{type: :object}},
        hosts: %Schema{type: :array, items: %Schema{type: :object}},
        glossary: %Schema{type: :array, items: %Schema{type: :object}},
        sources: %Schema{type: :array, items: %Schema{type: :object}},
        taxonomy: %Schema{type: :array, items: %Schema{type: :object}},
        places: %Schema{type: :array, items: %Schema{type: :object}}
      }
    })
  end

  defmodule TreeNode do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "TreeNode",
      description: "A node in the explore tree",
      type: :object,
      properties: %{
        key: %Schema{type: :string},
        label: %Schema{type: :string},
        url: %Schema{type: :string, nullable: true},
        nodes: %Schema{type: :array, items: %Schema{type: :object}}
      },
      required: [:key, :label]
    })
  end

  defmodule ExploreResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ExploreResponse",
      description: "Hierarchical tree data for exploring galls and hosts",
      type: :object,
      properties: %{
        galls: %Schema{type: :array, items: GallformersWeb.Schemas.TreeNode},
        undescribed: %Schema{type: :array, items: GallformersWeb.Schemas.TreeNode},
        hosts: %Schema{type: :array, items: GallformersWeb.Schemas.TreeNode}
      }
    })
  end

  defmodule FilterFields do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "FilterFields",
      description: "All available filter field options for the ID tool",
      type: :object,
      properties: %{
        alignments: %Schema{type: :array, items: GallformersWeb.Schemas.FilterField},
        cells: %Schema{type: :array, items: GallformersWeb.Schemas.FilterField},
        colors: %Schema{type: :array, items: GallformersWeb.Schemas.FilterField},
        forms: %Schema{type: :array, items: GallformersWeb.Schemas.FilterField},
        plant_parts: %Schema{type: :array, items: GallformersWeb.Schemas.FilterField},
        seasons: %Schema{type: :array, items: GallformersWeb.Schemas.FilterField},
        shapes: %Schema{type: :array, items: GallformersWeb.Schemas.FilterField},
        textures: %Schema{type: :array, items: GallformersWeb.Schemas.FilterField},
        walls: %Schema{type: :array, items: GallformersWeb.Schemas.FilterField}
      }
    })
  end

  defmodule Stats do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Stats",
      description: "Summary statistics about the database",
      type: :object,
      properties: %{
        galls: %Schema{type: :integer},
        hosts: %Schema{type: :integer},
        sources: %Schema{type: :integer},
        glossary: %Schema{type: :integer},
        undescribed_galls: %Schema{type: :integer},
        images: %Schema{type: :integer}
      }
    })
  end
end
