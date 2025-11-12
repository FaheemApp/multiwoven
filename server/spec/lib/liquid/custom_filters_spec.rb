# frozen_string_literal: true

require "rails_helper"

RSpec.describe Liquid::CustomFilters do
  include Liquid::CustomFilters

  describe ".cast" do
    it "casts input to string" do
      expect(cast(123, "string")).to eq("123")
    end

    it "casts input to number" do
      expect(cast("123.45", "number")).to eq(123.45)
    end

    it "casts non-numeric input to number as 0" do
      expect(cast("abc", "number")).to eq(0)
    end

    it "casts input to boolean" do
      expect(cast("true", "boolean")).to be true
    end
  end

  describe ".regex_replace" do
    it "replaces matching substrings" do
      expect(regex_replace("hello world", "world", "mars")).to eq("hello mars")
    end

    it "supports regex flags" do
      expect(regex_replace("Hello World", "world", "mars", "i")).to eq("Hello mars")
    end
  end

  describe ".to_datetime" do
    it "date format '%m/%d/%Y %H:%M'" do
      expect(to_datetime("1/26/2024 9:20", "%m/%d/%Y %H:%M")).to eq("2024-01-26T09:20:00+00:00")
    end

    it "date format '%m/%d/%Y %H:%M'" do
      expect(to_datetime("1/26/2024 9:20 AM", "%m/%d/%Y %H:%M")).to eq("2024-01-26T09:20:00+00:00")
    end

    it "handles nil value'" do
      expect(to_datetime(nil, "%m/%d/%Y %H:%M")).to eq(nil)
    end
  end

  describe ".parse_json" do
    it "parses valid JSON array" do
      expect(parse_json('["a", "b", "c"]')).to eq(["a", "b", "c"])
    end

    it "parses valid JSON object" do
      expect(parse_json('{"key": "value"}')).to eq({ "key" => "value" })
    end

    it "returns original string for invalid JSON" do
      expect(parse_json("not json")).to eq("not json")
    end

    it "returns nil for nil input" do
      expect(parse_json(nil)).to eq(nil)
    end

    it "returns empty string for empty input" do
      expect(parse_json("")).to eq("")
    end

    it "returns non-string input unchanged" do
      expect(parse_json([1, 2, 3])).to eq([1, 2, 3])
    end
  end

  describe ".to_json_array" do
    it "returns array unchanged" do
      expect(to_json_array(["a", "b", "c"])).to eq(["a", "b", "c"])
    end

    it "parses JSON array string" do
      expect(to_json_array('["a", "b", "c"]')).to eq(["a", "b", "c"])
    end

    it "splits comma-separated string" do
      expect(to_json_array("a,b,c")).to eq(["a", "b", "c"])
    end

    it "splits with custom delimiter" do
      expect(to_json_array("a|b|c", "|")).to eq(["a", "b", "c"])
    end

    it "trims whitespace from split values" do
      expect(to_json_array("a , b , c")).to eq(["a", "b", "c"])
    end

    it "returns empty array for blank input" do
      expect(to_json_array("")).to eq([])
      expect(to_json_array(nil)).to eq([])
    end

    it "wraps hash in array" do
      expect(to_json_array('{"key": "value"}')).to eq([{ "key" => "value" }])
    end

    it "wraps non-array/non-string in array" do
      expect(to_json_array(123)).to eq([123])
    end

    it "handles Arabic text in JSON array" do
      expect(to_json_array('["أول ثانوي", "ثاني ثانوي", "ثالث ثانوي"]')).to eq(["أول ثانوي", "ثاني ثانوي", "ثالث ثانوي"])
    end

    it "rejects blank values after split" do
      expect(to_json_array("a,,b,,c")).to eq(["a", "b", "c"])
    end
  end
end
