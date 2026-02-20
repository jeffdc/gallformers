defmodule Gallformers.Wcvp.TdwgTest do
  use ExUnit.Case, async: true

  alias Gallformers.Wcvp.Tdwg

  @test_mapping [
    %{
      "tdwg_code" => "CAL",
      "tdwg_name" => "California",
      "places" => [%{"code" => "US-CA", "precision" => "exact"}]
    },
    %{
      "tdwg_code" => "MEX",
      "tdwg_name" => "Mexico",
      "places" => [%{"code" => "MX", "precision" => "country"}]
    },
    %{
      "tdwg_code" => "BZL",
      "tdwg_name" => "Brazil South",
      "places" => [
        %{"code" => "BR-PR", "precision" => "exact"},
        %{"code" => "BR-SC", "precision" => "exact"},
        %{"code" => "BR-RS", "precision" => "exact"}
      ]
    }
  ]

  describe "build_lookup/1" do
    test "builds lookup from TDWG code to place entries" do
      lookup = Tdwg.build_lookup(@test_mapping)

      assert lookup["CAL"] == [%{code: "US-CA", precision: "exact"}]
      assert lookup["MEX"] == [%{code: "MX", precision: "country"}]
      assert length(lookup["BZL"]) == 3
    end
  end

  describe "convert_tdwg_codes/2" do
    test "converts list of TDWG codes to place code/precision pairs" do
      lookup = Tdwg.build_lookup(@test_mapping)
      result = Tdwg.convert_tdwg_codes(["CAL", "MEX", "BZL"], lookup)

      codes = Enum.map(result, & &1.code)
      assert "US-CA" in codes
      assert "MX" in codes
      assert "BR-PR" in codes
      assert "BR-SC" in codes
      assert "BR-RS" in codes
    end
  end

  describe "convert_tdwg_codes_with_warnings/2" do
    test "skips unknown TDWG codes and reports them" do
      lookup = Tdwg.build_lookup(@test_mapping)
      {result, unknown} = Tdwg.convert_tdwg_codes_with_warnings(["CAL", "ZZZ"], lookup)

      assert length(result) == 1
      assert unknown == ["ZZZ"]
    end
  end

  describe "us_canada_code?/1" do
    test "identifies US and Canadian place codes" do
      assert Tdwg.us_canada_code?("US-CA")
      assert Tdwg.us_canada_code?("CA-AB")
      refute Tdwg.us_canada_code?("MX")
      refute Tdwg.us_canada_code?("BR-PR")
    end
  end
end
