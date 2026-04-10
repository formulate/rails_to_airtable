module RailsAirtableSync
  module TypeSystem
    # Maps gem canonical types to Airtable field definition types (used when
    # creating or validating remote schema fields).
    #
    # Each entry is:
    #   gem_type => {
    #     airtable_type:  String   (the Airtable API "type" value),
    #     options:        Hash     (optional extra field options sent on creation),
    #     compatible:     [String] (remote types accepted as compatible)
    #   }
    AIRTABLE_TYPE_MAP = {
      string:               { airtable_type: "singleLineText",     options: {},               compatible: %w[singleLineText] },
      text:                 { airtable_type: "multilineText",      options: {},               compatible: %w[multilineText singleLineText] },
      integer:              { airtable_type: "number",             options: { precision: 0 }, compatible: %w[number currency percent] },
      float:                { airtable_type: "number",             options: { precision: 8 }, compatible: %w[number currency percent] },
      decimal:              { airtable_type: "number",             options: { precision: 8 }, compatible: %w[number currency percent] },
      boolean:              { airtable_type: "checkbox",           options: {},               compatible: %w[checkbox] },
      date:                 { airtable_type: "date",               options: { dateFormat: { name: "iso" } }, compatible: %w[date] },
      datetime:             { airtable_type: "dateTime",           options: { dateFormat: { name: "iso" }, timeFormat: { name: "24hour" }, timeZone: "utc" }, compatible: %w[dateTime] },
      email:                { airtable_type: "email",              options: {},               compatible: %w[email singleLineText] },
      url:                  { airtable_type: "url",                options: {},               compatible: %w[url singleLineText] },
      phone:                { airtable_type: "phoneNumber",        options: {},               compatible: %w[phoneNumber singleLineText] },
      single_select:        { airtable_type: "singleSelect",       options: {},               compatible: %w[singleSelect] },
      multi_select:         { airtable_type: "multipleSelects",    options: {},               compatible: %w[multipleSelects] },
      json:                 { airtable_type: "multilineText",      options: {},               compatible: %w[multilineText singleLineText] },
      attachment_url:       { airtable_type: "multipleAttachments",options: {},               compatible: %w[multipleAttachments] },
      lookup_string:        { airtable_type: "singleLineText",     options: {},               compatible: %w[singleLineText multilineText] },
      formula_safe_string:  { airtable_type: "singleLineText",     options: {},               compatible: %w[singleLineText] }
    }.freeze

    module_function

    def for_type(gem_type)
      AIRTABLE_TYPE_MAP.fetch(gem_type.to_sym) do
        raise ConfigurationError, "No Airtable type mapping for gem type :#{gem_type}"
      end
    end

    # Returns true if the remote Airtable field type is compatible with the
    # configured gem type (i.e. no destructive schema change required).
    def compatible?(gem_type, remote_airtable_type)
      entry = AIRTABLE_TYPE_MAP[gem_type.to_sym]
      return false unless entry

      entry[:compatible].include?(remote_airtable_type.to_s)
    end

    # Build the field creation body for the Airtable Metadata API.
    def field_definition(field_mapping)
      entry   = for_type(field_mapping.type)
      options = entry[:options].dup

      # Inject select options for single/multi-select fields if provided.
      if %i[single_select multi_select].include?(field_mapping.type) &&
         field_mapping.allowed_values&.any?
        options[:choices] = field_mapping.allowed_values.map { |v| { name: v } }
      end

      body = { name: field_mapping.airtable_field, type: entry[:airtable_type] }
      body[:options] = options unless options.empty?
      body
    end
  end
end
