# frozen_string_literal: true

require "rails_helper"
require "timecop"

RSpec.describe ReverseEtl::Transformers::UserMapping do
  describe "#transform" do
    let(:extractor) { ReverseEtl::Transformers::UserMapping.new }
    let(:sync) { instance_double("Sync", configuration: mapping) }
    let(:sync_record) { instance_double("SyncRecord", record: source_data) }
    let(:source_data) do
      { "cr_fee" => "57.82",
        "cr_item_sk" => "231891",
        "cr_net_loss" => "147.53",
        "cr_reason_sk" => "40",
        "cr_return_tax" => "2.33",
        "cr_order_number" => "14551370779",
        "cr_ship_mode_sk" => "5",
        "cr_store_credit" => "8.71",
        "cr_warehouse_sk" => "1",
        "cr_refunded_cash" => "62.15",
        "cr_return_amount" => "77.69",
        "cr_call_center_sk" => "54",
        "cr_catalog_page_sk" => "34956",
        "cr_return_quantity" => "17",
        "cr_reversed_charge" => "6.83",
        "cr_refunded_addr_sk" => "20717265",
        "cr_return_ship_cost" => "87.38",
        "cr_returned_date_sk" => "2452743",
        "cr_returned_time_sk" => "72108",
        "cr_refunded_cdemo_sk" => "1515291",
        "cr_refunded_hdemo_sk" => "5078",
        "cr_returning_addr_sk" => "7720298",
        "cr_return_amt_inc_tax" => "80.02",
        "cr_returning_cdemo_sk" => "598680",
        "cr_returning_hdemo_sk" => "2289",
        "cr_refunded_customer_sk" => "62244257",
        "cr_returning_customer_sk" => "39905396",
        "cr_text_field_sk" => "hello world" }
    end

    context "with complex mapping including arrays and nested structures" do
      let(:mapping) do
        { "cr_fee" => "attributes.properties.fee", "cr_item_sk" => "id" }
      end

      it "correctly handles complex transformations for each record" do
        results = extractor.transform(sync, sync_record)
        expected_result = {
          "attributes" => { "properties" => { "fee" => "57.82" } }, "id" => "231891"
        }

        expect(results).to eq(expected_result)
      end
    end

    context "when using standard, static, and template mapping" do
      let(:mapping) do
        [
          { mapping_type: "standard", from: "cr_item_sk", to: "id" },
          { mapping_type: "static", to: "attributes.properties.static_field", from: "static_value" },
          { mapping_type: "template", to: "attributes.properties.template_field",
            from: "Transformed {{cr_reason_sk}}" }
        ]
      end

      it "transforms record according to v2 mappings" do
        results = extractor.transform(sync, sync_record)
        expected_result = {
          "id" => "231891",
          "attributes" => {
            "properties" => {
              "static_field" => "static_value",
              "template_field" => "Transformed 40"
            }
          }
        }

        expect(results).to eq(expected_result)
      end
    end

    context "with template mapping using current date and time" do
      let(:sync) do
        instance_double("Sync", configuration: [
                          { mapping_type: "template",
                            to: "current_time",
                            from: "{{ 'now' | date: '%Y-%m-%dT%H:%M:%S.%L%z' }}" }
                        ])
      end
      let(:sync_record) { instance_double("SyncRecord", record: {}) }

      it "correctly renders the current time based on template" do
        Time.use_zone("UTC") do
          Timecop.freeze Time.zone.parse("2024-02-24T12:00:00Z") do
            results = extractor.transform(sync, sync_record)
            actual_datetime = DateTime.parse(results["current_time"])
            expected_datetime_str = "2024-02-24T12:00:00.000+0000"
            expected_datetime = DateTime.parse(expected_datetime_str)

            expect(actual_datetime).to eq(expected_datetime)
          end
        end
      end
    end

    context "when using different available filters for template mapping" do
      let(:mapping) do
        [
          { mapping_type: "template", to: "attributes.properties.cast_filter",
            from: "Transformed {{cr_reason_sk  | cast: 'number' }}" },
          { mapping_type: "template", to: "attributes.properties.regex_replace_field",
            from: "Transformed {{cr_reason_sk | regex_replace: '[0-9]+', 'Numbers'}}" }
        ]
      end

      it "transforms record according to v2 mappings" do
        results = extractor.transform(sync, sync_record)
        expected_result = {
          "attributes" => {
            "properties" => {
              "cast_filter" => "Transformed 40.0",
              "regex_replace_field" => "Transformed Numbers"
            }
          }
        }

        expect(results).to eq(expected_result)
      end
    end

    context "when using template mapping with JSON arrays" do
      let(:source_data) do
        {
          "levels_json" => '["أول ثانوي", "ثاني ثانوي", "ثالث ثانوي"]',
          "levels_comma" => "Math,Science,English",
          "tags" => '{"primary": "education", "secondary": "online"}'
        }
      end

      context "with parse_json filter" do
        let(:mapping) do
          [
            { mapping_type: "template", to: "levels_array",
              from: "{{ levels_json | parse_json }}" }
          ]
        end

        it "parses JSON string to array" do
          results = extractor.transform(sync, sync_record)
          expect(results["levels_array"]).to eq(["أول ثانوي", "ثاني ثانوي", "ثالث ثانوي"])
        end
      end

      context "with to_json_array filter" do
        let(:mapping) do
          [
            { mapping_type: "template", to: "levels_array",
              from: "{{ levels_comma | to_json_array }}" }
          ]
        end

        it "converts comma-separated string to array" do
          results = extractor.transform(sync, sync_record)
          expect(results["levels_array"]).to eq(["Math", "Science", "English"])
        end
      end

      context "with JSON output from template" do
        let(:mapping) do
          [
            { mapping_type: "template", to: "levels_array",
              from: '["level1", "level2", "level3"]' }
          ]
        end

        it "automatically parses JSON array output" do
          results = extractor.transform(sync, sync_record)
          expect(results["levels_array"]).to eq(["level1", "level2", "level3"])
        end
      end

      context "with JSON object output from template" do
        let(:mapping) do
          [
            { mapping_type: "template", to: "metadata",
              from: '{"key": "value", "count": 5}' }
          ]
        end

        it "automatically parses JSON object output" do
          results = extractor.transform(sync, sync_record)
          expect(results["metadata"]).to eq({ "key" => "value", "count" => 5 })
        end
      end

      context "with Arabic text in JSON array" do
        let(:mapping) do
          [
            { mapping_type: "template", to: "arabic_levels",
              from: "{{ levels_json | parse_json }}" }
          ]
        end

        it "correctly handles Arabic characters in JSON arrays" do
          results = extractor.transform(sync, sync_record)
          expect(results["arabic_levels"]).to eq(["أول ثانوي", "ثاني ثانوي", "ثالث ثانوي"])
        end
      end
    end

    context "when template output should be non-string primitives" do
      let(:mapping) do
        [
          { mapping_type: "template", to: "attributes.properties.boolean_flag",
            from: "{{ custom_boolean_field }}" },
          { mapping_type: "template", to: "attributes.properties.float_score",
            from: "{{ custom_float_field }}" },
          { mapping_type: "template", to: "attributes.properties.quantity",
            from: "{{ cr_return_quantity }}" },
          { mapping_type: "template", to: "attributes.properties.nil_field",
            from: "null" }
        ]
      end

      let(:source_data) do
        super().merge(
          "custom_boolean_field" => "False",
          "custom_float_field" => "19.5"
        )
      end

      it "casts booleans, floats, integers, and null literals" do
        results = extractor.transform(sync, sync_record)
        properties = results.dig("attributes", "properties")

        expect(properties["boolean_flag"]).to be false
        expect(properties["float_score"]).to eq(19.5)
        expect(properties["quantity"]).to eq(17)
        expect(properties["nil_field"]).to be_nil
      end
    end

    context "when using vector mapping" do
      let(:mapping) do
        [
          { mapping_type: "vector", from: "cr_text_field_sk", to: "vector_field",
            embedding_config: { "mode" => "open_ai", "model" => "text-embedding-ada-002", "api_key" => "api_key" } }
        ]
      end

      before do
        allow(ReverseEtl::Transformers::Embeddings::EmbeddingService)
          .to receive(:new)
          .and_return(
            double(
              "EmbeddingService",
              generate_embedding: [-0.038116533, 0.0021319648, -0.0045227623, -0.027926695]
            )
          )
      end

      it "applies the embedding transformation when embedding_config is present" do
        results = extractor.transform(sync, sync_record)
        expected_result = { "vector_field" => [-0.038116533, 0.0021319648, -0.0045227623, -0.027926695] }

        expect(results).to eq(expected_result)
      end

      it "falls back to the original value when no embedding_config is present" do
        mapping[0][:embedding_config] = nil
        results = extractor.transform(sync, sync_record)
        expected_result = { "vector_field" => "hello world" }

        expect(results).to eq(expected_result)
      end
    end
  end
end
