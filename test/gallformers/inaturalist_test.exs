defmodule Gallformers.INaturalistTest do
  use ExUnit.Case, async: true

  alias Gallformers.INaturalist

  describe "map_license/1" do
    test "maps iNat license codes to Gallformers licenses" do
      assert INaturalist.map_license("cc0") == "Public Domain / CC0"
      assert INaturalist.map_license("cc-by") == "CC-BY"
      assert INaturalist.map_license("cc-by-sa") == "CC-BY-SA"
      assert INaturalist.map_license("cc-by-nc") == "CC-BY-NC"
      assert INaturalist.map_license("cc-by-nc-sa") == "CC-BY-NC-SA"
      assert INaturalist.map_license("cc-by-nd") == "CC-BY-ND"
      assert INaturalist.map_license("cc-by-nc-nd") == "CC-BY-NC-ND"
    end

    test "maps nil to All Rights Reserved" do
      assert INaturalist.map_license(nil) == "All Rights Reserved"
    end
  end

  describe "parse_observation_id/1" do
    test "extracts ID from full URL" do
      assert INaturalist.parse_observation_id("https://www.inaturalist.org/observations/12345") ==
               {:ok, "12345"}
    end

    test "extracts ID from URL without www" do
      assert INaturalist.parse_observation_id("https://inaturalist.org/observations/12345") ==
               {:ok, "12345"}
    end

    test "extracts ID from URL with query string" do
      assert INaturalist.parse_observation_id(
               "https://www.inaturalist.org/observations/12345?locale=en"
             ) == {:ok, "12345"}
    end

    test "extracts ID from URL with fragment" do
      assert INaturalist.parse_observation_id(
               "https://www.inaturalist.org/observations/12345#activity"
             ) == {:ok, "12345"}
    end

    test "accepts bare numeric ID" do
      assert INaturalist.parse_observation_id("12345") == {:ok, "12345"}
    end

    test "rejects invalid input" do
      assert INaturalist.parse_observation_id("not-a-url") == {:error, :invalid_input}

      assert INaturalist.parse_observation_id("https://example.com/123") ==
               {:error, :invalid_input}

      assert INaturalist.parse_observation_id("") == {:error, :invalid_input}
    end
  end

  describe "parse_observation_response/1" do
    test "parses a valid observation response" do
      json = %{
        "results" => [
          %{
            "id" => 12_345,
            "taxon" => %{"name" => "Andricus quercuscalifornicus"},
            "user" => %{"login" => "janedoe", "name" => "Jane Doe"},
            "photos" => [
              %{
                "id" => 111,
                "url" => "https://inaturalist-open-data.s3.amazonaws.com/photos/111/square.jpg",
                "license_code" => "cc-by-nc"
              },
              %{
                "id" => 222,
                "url" => "https://static.inaturalist.org/photos/222/square.jpeg",
                "license_code" => nil
              }
            ]
          }
        ]
      }

      assert {:ok, obs} = INaturalist.parse_observation_response(json)
      assert obs.id == 12_345
      assert obs.taxon_name == "Andricus quercuscalifornicus"
      assert obs.observer_login == "janedoe"
      assert obs.observer_name == "Jane Doe"
      assert obs.url == "https://www.inaturalist.org/observations/12345"
      assert length(obs.photos) == 2

      [photo1, photo2] = obs.photos
      assert photo1.id == 111

      assert photo1.thumbnail_url ==
               "https://inaturalist-open-data.s3.amazonaws.com/photos/111/medium.jpg"

      assert photo1.original_url ==
               "https://inaturalist-open-data.s3.amazonaws.com/photos/111/original.jpg"

      assert photo1.mapped_license == "CC-BY-NC"
      assert photo1.all_rights_reserved? == false

      assert photo2.id == 222
      assert photo2.mapped_license == "All Rights Reserved"
      assert photo2.all_rights_reserved? == true
    end

    test "returns error for empty results" do
      json = %{"results" => []}
      assert {:error, :not_found} = INaturalist.parse_observation_response(json)
    end

    test "handles observation with no photos" do
      json = %{
        "results" => [
          %{
            "id" => 99_999,
            "taxon" => nil,
            "user" => %{"login" => "someone", "name" => nil},
            "photos" => []
          }
        ]
      }

      assert {:ok, obs} = INaturalist.parse_observation_response(json)
      assert obs.photos == []
      assert obs.taxon_name == nil
      assert obs.observer_name == nil
    end
  end

  describe "an observation's date, place, description and fields" do
    test "are parsed, a taxon field giving its taxon's name" do
      json = %{
        "results" => [
          %{
            "id" => 7,
            "user" => %{"login" => "someone"},
            "observed_on" => "2025-07-14",
            "place_guess" => "Berkeley, CA, USA",
            "place_ids" => [1, 14],
            "description" => "On a white oak.",
            "ofvs" => [
              %{
                "name" => "Host Plant ID",
                "value" => 54_779,
                "taxon" => %{"id" => 54_779, "name" => "Quercus alba"}
              },
              %{"name" => "Gallformers Code", "value" => "abc-1"}
            ],
            "photos" => []
          }
        ]
      }

      assert {:ok, obs} = INaturalist.parse_observation_response(json)
      assert obs.observed_on == ~D[2025-07-14]
      assert obs.place_ids == [1, 14]
      assert obs.place_guess == "Berkeley, CA, USA"
      assert obs.description == "On a white oak."
      assert INaturalist.field_value(obs, "host plant id") == "Quercus alba"
      assert INaturalist.field_value(obs, "Gallformers Code") == "abc-1"
      assert INaturalist.field_value(obs, "Other") == nil
    end
  end

  describe "fetch_places/1" do
    test "each place's name and admin level" do
      Req.Test.stub(INaturalist, fn conn ->
        assert conn.request_path == "/v1/places/1,14"

        Req.Test.json(conn, %{
          "results" => [
            %{"id" => 1, "name" => "United States", "admin_level" => 0},
            %{"id" => 14, "name" => "California", "admin_level" => 10}
          ]
        })
      end)

      assert {:ok, [%{id: 1, admin_level: 0}, %{id: 14, name: "California", admin_level: 10}]} =
               INaturalist.fetch_places([1, 14])
    end

    @tag :capture_log
    test "a failed request" do
      Req.Test.stub(INaturalist, &Req.Test.transport_error(&1, :timeout))
      assert {:error, %Req.TransportError{reason: :timeout}} = INaturalist.fetch_places([1])
    end
  end

  describe "format_creator/2" do
    test "formats login and name" do
      assert INaturalist.format_creator("janedoe", "Jane Doe") == "janedoe - Jane Doe"
    end

    test "uses login only when name is nil" do
      assert INaturalist.format_creator("janedoe", nil) == "janedoe"
    end

    test "uses login only when name is empty" do
      assert INaturalist.format_creator("janedoe", "") == "janedoe"
    end
  end
end
