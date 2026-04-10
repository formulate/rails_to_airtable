require "spec_helper"

RSpec.describe RailsAirtableSync::TypeSystem::Serializer do
  let(:config)     { RailsAirtableSync.configuration }
  let(:serializer) { described_class.new(config) }

  def mapping(type:, **opts)
    RailsAirtableSync::FieldMapping.new(
      "Test Field",
      from:     :value,
      type:     type,
      **opts
    )
  end

  describe "nil handling" do
    it "returns nil for nil value on nullable field" do
      m = mapping(type: :string, nullable: true)
      expect(serializer.serialize_field(nil, mapping: m)).to be_nil
    end

    it "raises ValidationError for nil on non-nullable field" do
      m = mapping(type: :string, nullable: false)
      expect { serializer.serialize_field(nil, mapping: m) }
        .to raise_error(RailsAirtableSync::ValidationError)
    end

    it "returns :omit when omit_on_nil is true and value is nil" do
      m = mapping(type: :string, omit_on_nil: true)
      expect(serializer.serialize_field(nil, mapping: m)).to eq :omit
    end

    it "uses default value when value is nil and default is set" do
      m = mapping(type: :string, default: "N/A")
      expect(serializer.serialize_field(nil, mapping: m)).to eq "N/A"
    end
  end

  describe ":string type" do
    it "converts to UTF-8 string" do
      m = mapping(type: :string)
      expect(serializer.serialize_field(42, mapping: m)).to eq "42"
    end

    it "strips invalid bytes" do
      m = mapping(type: :string)
      value = "hello\xFF"
      result = serializer.serialize_field(value, mapping: m)
      expect(result).to be_a(String)
      expect(result.encoding).to eq Encoding::UTF_8
    end

    it "enforces max_length" do
      m = mapping(type: :string, max_length: 5)
      expect { serializer.serialize_field("toolong", mapping: m) }
        .to raise_error(RailsAirtableSync::ValidationError, /max_length/)
    end
  end

  describe ":integer type" do
    it "passes Integer through" do
      m = mapping(type: :integer)
      expect(serializer.serialize_field(42, mapping: m)).to eq 42
    end

    it "raises for Float in strict mode" do
      m = mapping(type: :integer)
      expect { serializer.serialize_field(3.14, mapping: m) }
        .to raise_error(RailsAirtableSync::ValidationError, /Float/)
    end

    it "coerces Float when coerce: true" do
      m = mapping(type: :integer, coerce: true)
      expect(serializer.serialize_field(3.9, mapping: m)).to eq 3
    end

    it "raises for values outside safe JS integer range" do
      m = mapping(type: :integer)
      big = 2**54
      expect { serializer.serialize_field(big, mapping: m) }
        .to raise_error(RailsAirtableSync::ValidationError, /safe range/)
    end
  end

  describe ":boolean type" do
    it "serializes true" do
      m = mapping(type: :boolean)
      expect(serializer.serialize_field(true, mapping: m)).to eq true
    end

    it "serializes false" do
      m = mapping(type: :boolean)
      expect(serializer.serialize_field(false, mapping: m)).to eq false
    end

    it "raises for ambiguous string value" do
      m = mapping(type: :boolean)
      expect { serializer.serialize_field("yes", mapping: m) }
        .to raise_error(RailsAirtableSync::ValidationError)
    end
  end

  describe ":date type" do
    it "formats Date as ISO 8601 date" do
      m = mapping(type: :date)
      expect(serializer.serialize_field(Date.new(2024, 3, 15), mapping: m)).to eq "2024-03-15"
    end

    it "normalizes Time to UTC date" do
      m = mapping(type: :date)
      t = Time.at(0).utc  # 1970-01-01
      expect(serializer.serialize_field(t, mapping: m)).to eq "1970-01-01"
    end
  end

  describe ":datetime type" do
    it "formats Time as ISO 8601 UTC" do
      m = mapping(type: :datetime)
      t = Time.utc(2024, 1, 15, 12, 30, 0)
      expect(serializer.serialize_field(t, mapping: m)).to eq "2024-01-15T12:30:00Z"
    end
  end

  describe ":email type" do
    it "accepts valid email" do
      m = mapping(type: :email)
      expect(serializer.serialize_field("user@example.com", mapping: m)).to eq "user@example.com"
    end

    it "rejects invalid email" do
      m = mapping(type: :email)
      expect { serializer.serialize_field("not-an-email", mapping: m) }
        .to raise_error(RailsAirtableSync::ValidationError, /invalid email/)
    end
  end

  describe ":single_select type" do
    it "accepts allowed value" do
      m = mapping(type: :single_select, allowed_values: %w[active inactive])
      expect(serializer.serialize_field("active", mapping: m)).to eq "active"
    end

    it "rejects unknown value" do
      m = mapping(type: :single_select, allowed_values: %w[active inactive])
      expect { serializer.serialize_field("deleted", mapping: m) }
        .to raise_error(RailsAirtableSync::ValidationError, /unknown single_select/)
    end
  end

  describe ":multi_select type" do
    it "normalises and deduplicates array" do
      m = mapping(type: :multi_select, allowed_values: %w[a b c])
      result = serializer.serialize_field(%w[a b a], mapping: m)
      expect(result).to eq %w[a b]
    end

    it "rejects unknown values" do
      m = mapping(type: :multi_select, allowed_values: %w[a b])
      expect { serializer.serialize_field(%w[a z], mapping: m) }
        .to raise_error(RailsAirtableSync::ValidationError)
    end
  end

  describe ":json type" do
    it "serialises a Hash to compact JSON string" do
      m = mapping(type: :json)
      result = serializer.serialize_field({ key: "value" }, mapping: m)
      expect(JSON.parse(result)).to eq("key" => "value")
    end

    it "passes through a valid JSON string" do
      m = mapping(type: :json)
      expect(serializer.serialize_field('{"a":1}', mapping: m)).to eq '{"a":1}'
    end
  end

  describe ":url type" do
    it "accepts https URL" do
      m = mapping(type: :url)
      expect(serializer.serialize_field("https://example.com/path", mapping: m))
        .to eq "https://example.com/path"
    end

    it "rejects non-http URL" do
      m = mapping(type: :url)
      expect { serializer.serialize_field("ftp://files.example.com", mapping: m) }
        .to raise_error(RailsAirtableSync::ValidationError)
    end
  end

  describe ":attachment_url type" do
    it "wraps URL in attachment array format" do
      m = mapping(type: :attachment_url)
      result = serializer.serialize_field("https://example.com/file.pdf", mapping: m)
      expect(result).to eq [{ "url" => "https://example.com/file.pdf" }]
    end
  end
end
